"""Collect results in order, never missing or repeating one.

    python results.py           page through /v1/results from the saved cursor
    python results.py mk_...    the current result of one market
    python results.py ev_...    every market of one event, settled or pending

The cursor is kept in .results-cursor, so a second run picks up where the first stopped.
"""
import os
import sys

from odds_api import ApiError, get_json, main

CURSOR = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".results-cursor")
# SETTLED: settle bets. CORRECTED: re-settle. VOIDED: refund. UNSETTLED: hold.
# For one market, the entry with the highest seq is the current one.
TODO = {"SETTLED": "settle", "CORRECTED": "re-settle", "VOIDED": "refund stakes", "UNSETTLED": "hold settlement"}


def outcome(r):
    if r.get("winner"):
        return "winner " + r["winner"]["name"]
    if r.get("result") is not None:
        return f"result {r['result']}"
    return "no winner (void)"


def run():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg.startswith("mk_"):
        r = get_json(f"/v1/markets/{arg}/result")
        print(f"{r['event']['name']} / {r['market']['name']}: {r['status']}, {outcome(r)}"
              + (" (corrected)" if r.get("corrected") else "") + f", seq {r.get('seq', '-')}")
        return
    if arg.startswith("ev_"):
        for m in get_json(f"/v1/events/{arg}/results")["markets"]:
            print(f"{m['status']:<8} {m['market']['name']}" + ("" if m["status"] == "PENDING" else ": " + outcome(m)))
        return

    try:
        since = int(open(CURSOR).read().strip() or 0)
    except (OSError, ValueError):
        since = 0
    count = 0
    while True:
        try:
            page = get_json("/v1/results", {"since": since, "limit": 500})
        except ApiError as e:
            if e.status == 410:
                print("410 resync: cursor older than what is kept; starting from 0")
                since = 0
                continue
            raise
        for r in page["results"]:
            count += 1
            print(f"#{r['seq']} {r['action']:<9} {r['sport']} · {(r.get('event') or {}).get('name')} / "
                  f"{(r.get('market') or {}).get('name')}: {outcome(r)}  -> {TODO.get(r['action'], r['action'])}")
        since = page["next"]
        with open(CURSOR, "w") as f:
            f.write(str(since))
        if not page["more"]:  # while more is true, call again at once
            break
    print(f"{count} new result entries. Cursor saved: since={since}")


main(run)
