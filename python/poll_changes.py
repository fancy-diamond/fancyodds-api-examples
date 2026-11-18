"""No stream? Take a snapshot with /v1/odds, then poll /v1/changes with its token.

    python poll_changes.py [ev_a,ev_b]   (default: the first 5 events in play)

Runs until Ctrl-C. A 410 resync means the token is too old: snapshot again.
"""
import sys
import time

from odds_api import ApiError, describe_runner, get_json, inplay_event_ids, main

POLL_SECONDS = 2
book = {}


def snapshot(ids):
    res = get_json("/v1/odds", {"events": ",".join(ids)})
    book.clear()
    for ev in res["events"]:
        book[ev["id"]] = ev
    if res.get("missing"):
        print("not available:", ", ".join(res["missing"]))
    print(f"snapshot: {len(book)} events, token {res['next']}")
    return res["next"]


def apply(change):
    kind, d = change["type"], change["data"]
    ev = book.get(d.get("event") or d.get("id"))
    if kind == "market-update" and ev:
        m = d["market"]
        ev["markets"] = [x for x in ev["markets"] if x["id"] != m["id"]] + [m]
        r = (m.get("runners") or [None])[0]
        print(f"  {m['name']} [{m['status']}]" + (f"  {describe_runner(m, r)}" if r else ""))
    elif kind == "market-remove" and ev:
        ev["markets"] = [x for x in ev["markets"] if x["id"] != d["market"]]
        print(f"  removed {d['market']}")
    elif kind == "event-remove":
        book.pop(d["id"], None)
        print(f"  event ended {d['id']}")
    elif kind == "event-update" and ev:
        ev.update({k: v for k, v in d.items() if k != "markets"})
        print(f"  event {d.get('name')}: {d.get('state')}")


def run():
    ids = sys.argv[1].split(",") if len(sys.argv) > 1 else inplay_event_ids(5)
    if not ids:
        print("Nothing in play right now; pass event ids: python poll_changes.py ev_a,ev_b")
        return
    token = snapshot(ids)
    while True:
        time.sleep(POLL_SECONDS)
        try:
            res = get_json("/v1/changes", {"since": token, "events": ",".join(ids)})
        except ApiError as e:
            if e.status == 410:
                print("410 resync: token too old, taking a fresh snapshot")
                token = snapshot(ids)
                continue
            raise
        for c in res["changes"]:
            apply(c)
        print(f"{time.strftime('%H:%M:%S', time.gmtime())} {len(res['changes'])} changes, next {res['next']}")
        sys.stdout.flush()
        token = res["next"]


main(run)
