"""Fetch one event in full and print every market with its prices decoded.

    python event_markets.py [ev_...]   (default: the first event in play)
"""
import sys

from odds_api import get, inplay_event_ids, main, print_market

TYPES = ("match_odds", "bookmaker", "fancy")


def run():
    ids = sys.argv[1:2] or inplay_event_ids(1)
    if not ids:
        print("Nothing in play right now; pass an event id: python event_markets.py ev_...")
        return
    r = get("/v1/events/" + ids[0])
    ev = r.json()
    print(f"{ev['name']}  ({ev['sport']}, {ev['state']}, starts {ev['start']})")
    print(f"{len(ev['markets'])} markets. ETag {r.headers.get('ETag', '-')}; X-Resume-Token {r.headers.get('X-Resume-Token', '-')}\n")
    for t in TYPES:
        group = [m for m in ev["markets"] if m["type"] == t]
        if group:
            print(t.upper())
            for m in group:
                print_market(m)
            print()
    for m in ev["markets"]:
        if m["type"] not in TYPES:
            print_market(m)

    # Asking again with the ETag costs almost nothing while no price has moved.
    etag = r.headers.get("ETag")
    again = get("/v1/events/" + ids[0], headers={"If-None-Match": etag} if etag else None)
    print("Re-fetch with If-None-Match: 304 Not Modified (nothing changed)." if again.status_code == 304
          else f"Re-fetch: {again.status_code}, prices moved in between.")


main(run)
