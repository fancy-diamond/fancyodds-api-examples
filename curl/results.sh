#!/usr/bin/env bash
# Collect results in order, never missing or repeating one.
#   ./results.sh           page through /v1/results from the saved cursor
#   ./results.sh mk_...    the current result of one market
#   ./results.sh ev_...    every market of one event, settled or pending
# The cursor is kept in .results-cursor, so a second run picks up where the first stopped.
cd "$(dirname "$0")"; source ./common.sh

OUTCOME='def outcome: if .winner then "winner \(.winner.name)" elif .result != null then "result \(.result)" else "no winner (void)" end;'

case "${1:-}" in
  mk_*) api "/v1/markets/$1/result" | jq -r "$OUTCOME"'"\(.event.name) / \(.market.name): \(.status), \(outcome)\(if .corrected then " (corrected)" else "" end), seq \(.seq // "-")"'
        exit 0 ;;
  ev_*) api "/v1/events/$1/results" | jq -r "$OUTCOME"'.markets[] | "\(.status)\t\(.market.name)\(if .status == "PENDING" then "" else ": " + outcome end)"'
        exit 0 ;;
esac

# SETTLED: settle bets. CORRECTED: re-settle. VOIDED: refund. UNSETTLED: hold.
# For one market, the entry with the highest seq is the current one.
SINCE=$(cat .results-cursor 2>/dev/null || echo 0)
while true; do
  if ! api /v1/results -G --data-urlencode "since=$SINCE" --data-urlencode limit=500 > "$TMP/r.json"; then
    echo "410 resync: cursor older than what is kept; starting from 0"; SINCE=0; continue
  fi
  jq -r "$OUTCOME"'
    {"SETTLED": "settle", "CORRECTED": "re-settle", "VOIDED": "refund stakes", "UNSETTLED": "hold settlement"} as $todo |
    .results[] | "#\(.seq) \(.action)\t\(.sport) · \(.event.name) / \(.market.name): \(outcome)  -> \($todo[.action] // .action)"' "$TMP/r.json"
  SINCE=$(jq -r .next "$TMP/r.json")
  echo "$SINCE" > .results-cursor
  [ "$(jq -r .more "$TMP/r.json")" = true ] || break   # while more is true, call again at once
done
echo "Cursor saved: since=$SINCE"
