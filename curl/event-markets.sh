#!/usr/bin/env bash
# Fetch one event in full and print every market with its prices decoded.
#   ./event-markets.sh [ev_...]   (default: the first event in play)
cd "$(dirname "$0")"; source ./common.sh

ID="${1:-$(inplay_ids 1)}"
[ -n "$ID" ] || { echo "Nothing in play right now; pass an event id: ./event-markets.sh ev_..."; exit 0; }

api "/v1/events/$ID" > "$TMP/event.json"
ETAG=$(awk -F': ' 'tolower($1)=="etag"{print $2}' "$TMP/h" | tr -d '\r')
jq -r "$JQ_PRICES"'
  "\(.name)  (\(.sport), \(.state), starts \(.start))", "\(.markets | length) markets\n",
  (. as $ev | ["match_odds", "bookmaker", "fancy"][] as $t
     | ($ev.markets | map(select(.type == $t))) as $g
     | if ($g | length) > 0 then ($t | ascii_upcase), ($g[] | print_market), "" else empty end),
  (.markets[] | select(.type | IN("match_odds", "bookmaker", "fancy") | not) | print_market)' "$TMP/event.json"

# Asking again with the ETag costs almost nothing while no price has moved.
if [ -n "$ETAG" ]; then
  api "/v1/events/$ID" -H "If-None-Match: $ETAG" >/dev/null
  [ "$(head -1 "$TMP/h" | awk '{print $2}')" = 304 ] && echo "Re-fetch with If-None-Match: 304 Not Modified (nothing changed)." \
    || echo "Re-fetch: prices moved in between."
fi
