"""Print a fancy / session board: each market's No and Yes, as line · rate.

    python fancy_board.py [ev_...] [--watch]

Default: the first cricket event in play that has fancy markets. --watch
re-reads the event every 3 s with If-None-Match, so an unchanged board costs a
304 and no body.

Fancy markets come in three formats:
  line     price = the line, size = the rate. Back is Yes, lay is No.
           Yes 100 at 91 · 90 wins 90 if the result reaches 91.
           No 100 at 91 · 110 wins 100 if it stays below 91, else loses 110.
  range    khado: Yes only, from `price` upward over a width of scores, size = the rate.
  decimal  Odd/Even and similar Yes/No markets in plain decimal odds.
"""
import sys
import time

from odds_api import get, get_json, main, tradeable


def pick_event():
    events = get_json("/v1/events", {"sport": "cricket", "state": "inplay"})["events"]
    for e in events[:5]:
        if any(m["type"] == "fancy" for m in get("/v1/events/" + e["id"]).json()["markets"]):
            return e["id"]
    return events[0]["id"] if events else None


def cell(lvl):
    return f"{lvl['price']:g} · {lvl['size']:g}" if lvl else "—"


def first(ladder):
    return ladder[0] if ladder else None


def board(ev):
    fancy = [m for m in ev["markets"] if m["type"] == "fancy"]
    print(f"\n{ev['name']}   {time.strftime('%H:%M:%S', time.gmtime(ev['updatedAt'] / 1000))} UTC   {len(fancy)} fancy markets\n")
    print(f"{'Market':<34}{'No':<14}{'Yes':<14}Status")
    print("-" * 76)
    for m in fancy:
        r = (m.get("runners") or [{}])[0]
        status = "OPEN" if tradeable(m, r) else ("SUSPENDED (stale)" if m.get("stale") else m["status"]) + ", no bets"
        if m["format"] == "line":
            print(f"{m['name'][:33]:<34}{cell(first(r.get('lay'))):<14}{cell(first(r.get('back'))):<14}{status}")
        elif m["format"] == "range":
            w = r.get("width", m.get("width"))
            yes = cell(first(r.get("back"))) + (f" w{w}" if w else "")
            print(f"{m['name'][:33]:<34}{'—':<14}{yes:<14}{status}  (khado)")
        else:
            for x in m["runners"]:
                b = first(x.get("back"))
                print(f"{(m['name'] + ' · ' + x['name'])[:33]:<34}{'—':<14}{(format(b['price'], 'g') if b else '—'):<14}{status}  (decimal)")
    for m in fancy:
        r = (m.get("runners") or [{}])[0]
        if m["format"] == "line" and tradeable(m) and first(r.get("back")) and first(r.get("lay")):
            y, n = r["back"][0], r["lay"][0]
            print(f"\nReading \"{m['name']}\": Yes 100 at {y['price']:g} wins {y['size']:g} on {y['price']:g}+ runs. "
                  f"No 100 at {n['price']:g} wins 100 below {n['price']:g}, else loses {n['size']:g}.")
            break


def run():
    args = sys.argv[1:]
    watch = "--watch" in args
    ids = [a for a in args if a.startswith("ev_")]
    event_id = ids[0] if ids else pick_event()
    if not event_id:
        print("No cricket in play right now; pass an event id: python fancy_board.py ev_...")
        return
    etag = None
    while True:
        r = get("/v1/events/" + event_id, headers={"If-None-Match": etag} if etag else None)
        if r.status_code != 304:
            etag = r.headers.get("ETag")
            board(r.json())
        if not watch:
            break
        time.sleep(3)


main(run)
