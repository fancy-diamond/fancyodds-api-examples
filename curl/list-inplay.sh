#!/usr/bin/env bash
# List the events in play now.
#   ./list-inplay.sh [sport]     e.g. cricket, soccer, tennis (default: cricket)
cd "$(dirname "$0")"; SPORT="${1-${SPORT-cricket}}"; source ./common.sh

api /v1/me | jq -r '"Key for \(.client); sports on your plan: \(.sports | join(", "))",
  (if (.limits.delayMs // 0) > 0 then "Prices on this key are delayed \(.limits.delayMs / 1000) s." else empty end)'

api /v1/events -G --data-urlencode state=inplay ${SPORT:+--data-urlencode "sport=$SPORT"} | jq -r --arg sport "$SPORT" '
  if (.events | length) == 0 then "Nothing in play\(if $sport != "" then " for " + $sport else "" end) right now. Try: ./list-inplay.sh soccer"
  else
    "\n\(.events | length) in play\(if $sport != "" then " (" + $sport + ")" else "" end):\n",
    (.events[] | "\(.id)  \(.sport)\t\(.name)",
                 "\(" " * (.id | length))  \(.competition.name // "") · \(.marketCount) markets · last price change \((now - .updatedAt / 1000) | floor) s ago")
  end'
