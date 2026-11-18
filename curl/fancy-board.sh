#!/usr/bin/env bash
# Print a fancy / session board: each market's No and Yes, as line · rate.
#   ./fancy-board.sh [ev_...]   (default: the first cricket match in play with fancy markets)
#
# line   price = the line, size = the rate. Back is Yes, lay is No.
#        Yes 100 at 91 · 90 wins 90 if the result reaches 91.
#        No 100 at 91 · 110 wins 100 if it stays below 91, else loses 110.
# range  khado: Yes only, from `price` upward, size = the rate.
cd "$(dirname "$0")"; SPORT=cricket; source ./common.sh

# the first in-play match that has fancy markets (the first one may have none)
ID="${1:-}"
if [ -z "$ID" ]; then
  for e in $(inplay_ids 5 | tr ',' ' '); do
    if [ "$(api "/v1/events/$e" | jq '[.markets[] | select(.type == "fancy")] | length')" -gt 0 ]; then ID=$e; break; fi
    sleep 0.6   # sandbox: 2 requests a second
  done
fi
[ -n "$ID" ] || { echo "No cricket in play right now; pass an event id: ./fancy-board.sh ev_..."; exit 0; }

api "/v1/events/$ID" | jq -r "$JQ_PRICES"'
  def cell($l): if $l then "\($l.price) · \($l.size)" else "—" end;
  def pad($n): . + " " * ([$n - length, 0] | max);
  def status($m): if $m.status == "OPEN" and ($m.stale | not) then "OPEN" elif $m.stale then "SUSPENDED (stale), no bets" else "\($m.status), no bets" end;
  [.markets[] | select(.type == "fancy")] as $f |
  "\n\(.name)   \(.updatedAt / 1000 | floor | strftime("%H:%M:%S")) UTC   \($f | length) fancy markets\n",
  "\("Market" | pad(34))\("No" | pad(14))\("Yes" | pad(14))Status",
  ("-" * 76),
  ($f[] | . as $m | (.runners[0] // {}) as $r |
    if   .format == "line"  then "\(.name[:33] | pad(34))\(cell($r.lay[0]?) | pad(14))\(cell($r.back[0]?) | pad(14))\(status($m))"
    elif .format == "range" then "\(.name[:33] | pad(34))\("—" | pad(14))\(cell($r.back[0]?) | pad(14))\(status($m))  (khado)"
    else (.runners[] | "\("\($m.name) · \(.name)"[:33] | pad(34))\("—" | pad(14))\((.back[0].price // "—") | tostring | pad(14))\(status($m))  (decimal)")
    end),
  ([$f[] | select(.format == "line" and .status == "OPEN" and (.stale | not) and .runners[0].back[0] and .runners[0].lay[0])][0]
    | if . then .runners[0].back[0] as $y | .runners[0].lay[0] as $n |
      "\nReading \"\(.name)\": Yes 100 at \($y.price) wins \($y.size) on \($y.price)+ runs. No 100 at \($n.price) wins 100 below \($n.price), else loses \($n.size)."
      else empty end)'
