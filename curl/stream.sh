#!/usr/bin/env bash
# Open the live stream with curl, resuming with Last-Event-ID.
#   ./stream.sh                 the first 5 events in play (sandbox keys list up to 5 ids)
#   ./stream.sh ev_a,ev_b       these events
#   ./stream.sh all             everything on your plan (live keys only)
# Runs until Ctrl-C.
#
# How it stays alive:
#  - every message has an id; we keep the last one and send it back as
#    Last-Event-ID when we reconnect, so nothing is missed;
#  - a `reconnect` message (about every 14 minutes, and before a server
#    restart) means: close and reconnect now;
#  - a dropped connection, including a 15-minute (900 s) cut by a proxy, is
#    resumed the same way after a short pause;
#  - `: heartbeat` arrives every 15 s; curl gives up after 45 s with no bytes
#    (--speed-limit 1 --speed-time 45) and we reconnect.
cd "$(dirname "$0")"; source ./common.sh

EVENTS="${1:-$(inplay_ids 5)}"
[ -n "$EVENTS" ] || { echo "Nothing in play right now; pass event ids: ./stream.sh ev_a,ev_b"; exit 0; }

FIFO="$TMP/sse"; mkfifo "$FIFO"
LAST_ID=""
RETRY_S=1
CURL_PID=""
trap '[ -n "$CURL_PID" ] && kill "$CURL_PID" 2>/dev/null; rm -rf "$TMP"' EXIT
trap 'exit 0' INT TERM

show() { # show EVENT DATA
  jq -r --arg ev "$1" "$JQ_PRICES"'
    (now | strftime("%H:%M:%S")) as $t |
    if   $ev == "snapshot"      then "\($t) snapshot       \(.name): \(.markets | length) markets"
    elif $ev == "ready"         then "\($t) ready          opening snapshots done; changes from here on"
    elif $ev == "market-update" then .market as $m | "\($t) market-update  \($m.name) [\($m | flag)]  \(($m.runners // [])[0] | if . then "\(.name): " + describe($m) else "" end)"
    elif $ev == "market-remove" then "\($t) market-remove  \(.market) (its result follows)"
    elif $ev == "event-update"  then "\($t) event-update   \(.name): \(.state)"
    elif $ev == "event-remove"  then "\($t) event-remove   \(.id)"
    elif $ev == "result"        then "\($t) result         #\(.seq) \(.action) \(.market.name): \(if .winner then "winner " + .winner.name elif .result != null then "result \(.result)" else "void" end)"
    else "\($t) \($ev)" end' <<<"$2"
}

while true; do
  echo "[stream] connecting${LAST_ID:+, resuming after $LAST_ID}" >&2
  # Headers go in a file inside our private temp dir, so the key stays out of the process list.
  { key_header; if [ -n "$LAST_ID" ]; then printf 'Last-Event-ID: %s\n' "$LAST_ID"; fi; } > "$TMP/hdr"
  curl -sS -N -H @"$TMP/hdr" -H 'Accept: text/event-stream' -A "$UA" -D "$TMP/sh" \
        --connect-timeout 10 --speed-limit 1 --speed-time 45 \
        "$BASE/v1/stream?events=$EVENTS" > "$FIFO" 2>"$TMP/err" &
  CURL_PID=$!

  ROTATE=""; EVENT="message"; DATA=""; ID=""; BODY=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ -z "$line" ]; then                       # end of one message
      [ -n "$ID" ] && LAST_ID="$ID"
      if [ -n "$DATA" ]; then
        case "$EVENT" in
          reconnect) echo "[stream] server asked us to reconnect" >&2; ROTATE=1; kill "$CURL_PID" 2>/dev/null; break ;;
          error) echo "[stream] error: $DATA" >&2; exit 1 ;;
          *) show "$EVENT" "$DATA" ;;
        esac
      fi
      EVENT="message"; DATA=""; ID=""
      continue
    fi
    case "$line" in
      :*) ;;                                      # comment, e.g. ": heartbeat"
      event:*) EVENT="${line#event:}"; EVENT="${EVENT# }" ;;
      data:*)  v="${line#data:}"; v="${v# }"; DATA="${DATA:+$DATA$'\n'}$v" ;;
      id:*)    ID="${line#id:}"; ID="${ID# }" ;;
      retry:*) v="${line#retry:}"; v="${v# }"; [[ "$v" =~ ^[0-9]+$ ]] && RETRY_S=$(( (v + 999) / 1000 )) ;;
      *) BODY="$BODY$line" ;;                     # not SSE: an error body
    esac
  done < "$FIFO"
  wait "$CURL_PID" 2>/dev/null || true
  CURL_PID=""

  STATUS=$(head -1 "$TMP/sh" 2>/dev/null | awk '{print $2}')
  case "$STATUS" in
    400|401|403|404) echo "$STATUS $BODY" >&2; exit 1 ;;
    429|503) echo "[stream] $STATUS $BODY; retrying in 10 s" >&2; sleep 10; continue ;;
  esac
  [ -n "$ROTATE" ] && continue                    # reconnect at once
  echo "[stream] connection lost $(tr -d '\n' < "$TMP/err")" >&2
  sleep $(( RETRY_S + RANDOM % 2 ))
done
