"""Open the live stream and keep a local copy of every market current.

    python stream.py                 the first 5 events in play (sandbox keys list up to 5 ids)
    python stream.py ev_a,ev_b       these events
    python stream.py all             everything on your plan (live keys only)

Runs until Ctrl-C. Resume, reconnect and heartbeats are handled in odds_api.stream().
"""
import sys
import time

from odds_api import BASE, describe_runner, inplay_event_ids, is_sandbox_key, main, stream, tradeable

book = {}  # event id -> event, as the API sends it


def t():
    return time.strftime("%H:%M:%S", time.gmtime())


def upsert_market(event_id, market):
    ev = book.get(event_id)
    if not ev:
        return
    for i, m in enumerate(ev["markets"]):
        if m["id"] == market["id"]:
            ev["markets"][i] = market  # a market-update is the whole market: replace, never merge
            return
    ev["markets"].append(market)


def on_message(kind, data, last_id):
    if kind == "snapshot":
        book[data["id"]] = data
        print(f"{t()} snapshot       {data['name']}: {len(data['markets'])} markets")
    elif kind == "ready":
        print(f"{t()} ready          {len(book)} events loaded; changes from here on (last id {last_id})")
    elif kind == "market-update":
        m = data["market"]
        upsert_market(data["event"], m)
        state = "OPEN" if tradeable(m) else (f"{m['status']}, stale" if m.get("stale") else m["status"])
        r = (m.get("runners") or [None])[0]
        print(f"{t()} market-update  {m['name']} [{state}]" + (f"  {r['name']}: {describe_runner(m, r)}" if r else ""))
    elif kind == "market-remove":
        ev = book.get(data["event"])
        if ev:
            ev["markets"] = [m for m in ev["markets"] if m["id"] != data["market"]]
        print(f"{t()} market-remove  {data['market']} (its result follows)")
    elif kind == "event-update":
        old = book.get(data["id"], {})
        book[data["id"]] = {**old, **data, "markets": old.get("markets", [])}
        print(f"{t()} event-update   {data.get('name')}: {data.get('state')}")
    elif kind == "event-remove":
        book.pop(data["id"], None)
        print(f"{t()} event-remove   {data['id']}")
    elif kind == "result":
        what = ("winner " + data["winner"]["name"]) if data.get("winner") else (
            f"result {data['result']}" if data.get("result") is not None else "void")
        print(f"{t()} result         #{data['seq']} {data['action']} {data['market']['name']}: {what}")
    else:
        print(f"{t()} {kind}")
    sys.stdout.flush()


def run():
    events = sys.argv[1] if len(sys.argv) > 1 else ",".join(inplay_event_ids(5 if is_sandbox_key() else 50))
    if not events:
        print("Nothing in play right now; pass event ids: python stream.py ev_a,ev_b")
        return
    stream(f"{BASE}/v1/stream?events={events}", on_message)


main(run)
