#!/usr/bin/env bash
# No stream? Take a snapshot with /v1/odds, then poll /v1/changes with its token.
#   ./poll-changes.sh [ev_a,ev_b]   (default: the first 5 events in play)
# Runs until Ctrl-C. A 410 resync means the token is too old: snapshot again.
cd "$(dirname "$0")"; source ./common.sh

IDS="${1:-$(inplay_ids 5)}"
[ -n "$IDS" ] || { echo "Nothing in play right now; pass event ids: ./poll-changes.sh ev_a,ev_b"; exit 0; }

snapshot() {
  api /v1/odds -G --data-urlencode "events=$IDS" > "$TMP/odds.json"
  jq -r '(if (.missing | length) > 0 then "not available: \(.missing | join(", "))" else empty end),
         "snapshot: \(.events | length) events, token \(.next)"' "$TMP/odds.json"
  NEXT=$(jq -r .next "$TMP/odds.json")
}
snapshot

while true; do
  sleep 2
  sleep 0.55
  status=$(key_header | curl -sS --compressed -H @- -A "$UA" -o "$TMP/c" -w '%{http_code}' -G \
    --data-urlencode "since=$NEXT" --data-urlencode "events=$IDS" "$BASE/v1/changes")
  if [ "$status" = 410 ]; then echo "410 resync: token too old, taking a fresh snapshot"; snapshot; continue; fi
  if [ "$status" = 429 ]; then sleep 1; continue; fi
  if [ "$status" -ge 400 ]; then echo "$status $(cat "$TMP/c")" >&2; exit 1; fi
  jq -r "$JQ_PRICES"'
    (.changes[] | . as $c |
      if   $c.type == "market-update" then $c.data.market as $m | "  \($m.name) [\($m.status)]  \(($m.runners // [])[0] | if . then describe($m) else "" end)"
      elif $c.type == "market-remove" then "  removed \($c.data.market)"
      elif $c.type == "event-remove"  then "  event ended \($c.data.id)"
      elif $c.type == "event-update"  then "  event \($c.data.name): \($c.data.state)"
      else "  \($c.type)" end),
    "\(now | strftime("%H:%M:%S")) \(.changes | length) changes, next \(.next)"' "$TMP/c"
  NEXT=$(jq -r .next "$TMP/c")
done
