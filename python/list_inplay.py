"""List the events in play now.

    python list_inplay.py [sport]     e.g. cricket, soccer, tennis (default: cricket)
"""
import sys
import time

from odds_api import DEFAULT_SPORT, get_json, main


def run():
    sport = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SPORT
    me = get_json("/v1/me")
    print(f"Key for {me['client']}; sports on your plan: {', '.join(me['sports'])}")
    if me.get("limits", {}).get("delayMs"):
        print(f"Prices on this key are delayed {me['limits']['delayMs'] / 1000:g} s.")

    events = get_json("/v1/events", {"state": "inplay", "sport": sport})["events"]
    if not events:
        print(f"Nothing in play{' for ' + sport if sport else ''} right now. Try: python list_inplay.py soccer")
        return
    print(f"\n{len(events)} in play{' (' + sport + ')' if sport else ''}:\n")
    for e in events:
        age = round(time.time() - e["updatedAt"] / 1000)
        print(f"{e['id']}  {e['sport']:<8} {e['name']}")
        print(f"{' ' * len(e['id'])}  {(e.get('competition') or {}).get('name', '')} · {e['marketCount']} markets · last price change {age} s ago")


main(run)
