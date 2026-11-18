# Shared helpers for the curl examples. Needs bash, curl and jq.
#
#   FANCYODDS_KEY       your key (fg_test_... for the sandbox, fg_live_... for live)
#   FANCYODDS_BASE_URL  optional, defaults to the sandbox: https://api-sandbox.fancyodds.live

set -euo pipefail

BASE="${FANCYODDS_BASE_URL:-https://api-sandbox.fancyodds.live}"
BASE="${BASE%/}"
SPORT="${SPORT-cricket}"
UA="fancyodds-api-examples/1.0"

command -v jq >/dev/null || { echo "These examples need jq: https://jqlang.github.io/jq/" >&2; exit 2; }
if [ -z "${FANCYODDS_KEY:-}" ]; then
  echo "Set FANCYODDS_KEY first. Ask for a sandbox key at https://fancyodds.live/telegram" >&2
  exit 2
fi

# The key goes to curl on stdin (-H @-), so it never shows in the process list.
key_header() { printf 'X-API-Key: %s\n' "$FANCYODDS_KEY"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# api PATH [curl args...]  ->  JSON body on stdout. Exits on an API error.
# Spaces calls 0.55 s apart (the sandbox allows 2 requests per second) and
# retries 429 rate_limited / 503 starting after Retry-After.
api() {
  local path="$1"; shift
  local attempt status code
  for attempt in 1 2 3 4 5; do
    sleep 0.55
    status=$(key_header | curl -sS --compressed -H @- -H 'Accept: application/json' -A "$UA" \
      -D "$TMP/h" -o "$TMP/b" -w '%{http_code}' "$@" "$BASE$path")
    if [ "$status" -lt 400 ]; then cat "$TMP/b"; return 0; fi
    [ "$status" = 410 ] && return 10   # resync: the caller takes a fresh snapshot / cursor
    code=$(jq -r '.code // empty' "$TMP/b" 2>/dev/null || true)
    if { [ "$status" = 429 ] && [ "$code" = rate_limited ]; } || { [ "$status" = 503 ] && [ "$code" = starting ]; }; then
      local after; after=$(awk -F': ' 'tolower($1)=="retry-after"{print $2+0}' "$TMP/h"); after=${after:-2}
      echo "... $code, retrying in ${after}s" >&2; sleep "$after"; continue
    fi
    echo "$status $(jq -r '"\(.code): \(.message)"' "$TMP/b" 2>/dev/null || cat "$TMP/b")" \
      "(X-Request-Id $(awk -F': ' 'tolower($1)=="x-request-id"{print $2}' "$TMP/h" | tr -d '\r'))" >&2
    [ "$status" = 403 ] && echo "Requests are accepted only from IPs on your allowlist, and a key works only in its own environment." >&2
    exit 1
  done
}

inplay_ids() { # inplay_ids LIMIT  ->  "ev_a,ev_b"
  api "/v1/events" -G --data-urlencode "state=inplay" ${SPORT:+--data-urlencode "sport=$SPORT"} \
    | jq -r --argjson n "$1" '[.events[:$n][].id] | join(",")'
}

# jq helpers for reading prices. Always read `format` first:
#   decimal  price = decimal odds, size = amount available
#   rate     bookmaker: profit per 100 staked; decimal = 1 + rate / 100
#   line     fancy: price = the line, size = the rate; back = Yes, lay = No
#   range    khado: price = first winning score, size = the rate; back only
JQ_PRICES='
def best($side): (.[$side] // [])[0];
def tradeable($m): $m.status == "OPEN" and ($m.stale | not) and ((.status // "OPEN") == "OPEN");
def describe($m):
  best("back") as $b | best("lay") as $l |
  if   $m.format == "decimal" then "back \(if $b then "\($b.price) x \($b.size)" else "-" end)  |  lay \(if $l then "\($l.price) x \($l.size)" else "-" end)"
  elif $m.format == "rate"    then "back \(if $b then "\($b.price) (decimal \(1 + $b.price / 100))" else "-" end)  |  lay \(if $l then "\($l.price) (decimal \(1 + $l.price / 100))" else "-" end)"
  elif $m.format == "line"    then "No \(if $l then "\($l.price) · \($l.size)" else "-" end)  |  Yes \(if $b then "\($b.price) · \($b.size)" else "-" end)"
  elif $m.format == "range"   then "Yes from \(if $b then "\($b.price) · \($b.size)" else "-" end)\((.width // $m.width) as $w | if $w and $b then "  width \($w) (wins on \($b.price) to \($b.price + $w - 1))" else "" end)"
  else "unknown format \($m.format)" end;
def flag: if .stale then "\(.status), stale" else .status end;
def print_market:
  . as $m |
  "  [\($m | flag)] \($m.name)  (\($m.type), \($m.format))\(if $m.status == "OPEN" and ($m.stale | not) then "" else "   <- no bets" end)",
  ($m.runners[]? | "      \((.name + (if (.status // "OPEN") != "OPEN" then " [\(.status)]" else "" end)) | . + " " * ([28 - length, 0] | max)) \(describe($m))");
'
