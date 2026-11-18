# Fancy API and cricket odds API examples

Working code for the **[Fancy Odds API](https://fancyodds.live)**: live **fancy and session odds**, **bookmaker rates**, **match odds** and **results** for cricket, plus soccer, tennis and more, over REST and Server-Sent Events. Examples in **Node.js, Python, PHP and curl**, each one a single file you can read in a few minutes.

API reference: **https://docs.fancyodds.live** · Website: **https://fancyodds.live** · Get a sandbox key: **https://fancyodds.live/telegram**

> Fancy Odds is an independent API provider, not run by or affiliated with Diamond Exchange or Betfair.

## Contents

- [What the feed is](#what-the-feed-is)
- [Quickstart](#quickstart)
- [The examples](#the-examples)
- [Reading prices: decimal, rate, line and range](#reading-prices-decimal-rate-line-and-range)
- [Fancy and session markets: Yes and No](#fancy-and-session-markets-yes-and-no)
- [Market status and suspended markets](#market-status-and-suspended-markets)
- [Keeping a live odds stream alive](#keeping-a-live-odds-stream-alive)
- [Polling instead of streaming](#polling-instead-of-streaming)
- [Results and settlement](#results-and-settlement)
- [Sandbox limits](#sandbox-limits)
- [Errors](#errors)
- [Running each language](#running-each-language)
- [OpenAPI spec](#openapi-spec)
- [Postman collection](#postman-collection)
- [Get an API key](#get-an-api-key)

## What the feed is

A live **cricket odds API** for betting operators. You get every market on a match as structured JSON: the **fancy / session** board (6, 10, 15 and 20 over runs, lambi, fall of wicket, player runs, khado, odd/even), the **bookmaker** market, and **match odds** with back and lay prices. Prices move in real time from pre-match to the last ball, and each market's result is published when it settles, so you can settle bets automatically.

- **REST** for snapshots: list events, fetch one event with every market and price, batch odds for up to 50 events, look up results.
- **A live stream (SSE)**: one long HTTP response that sends each event in full, then only what changes, usually within a fraction of a second. No WebSocket needed; any HTTP client can read it.
- **A changes feed** for servers that cannot hold a stream open.
- **Results** pushed on the stream and kept for at least 48 hours.
- Stable ids that never change: `ev_…` events, `mk_…` markets, `rn_…` runners, `cp_…` competitions.

The API is for **server-to-server** use. Keys work only from the server IPs you register, so do not call it from a browser or an app.

## Quickstart

```bash
export FANCYODDS_KEY="fg_test_…"           # your sandbox key, from https://fancyodds.live/telegram
cd fancyodds-api-examples
node node/list-inplay.mjs                # what is in play now
node node/event-markets.mjs              # one event, every market, prices decoded
node node/fancy-board.mjs                # the fancy / session board, Yes and No
node node/stream.mjs                     # live stream, Ctrl-C to stop
```

Node 18 or newer, nothing to install. The same examples exist in Python, PHP and curl: see [Running each language](#running-each-language).

Every example reads the key from `FANCYODDS_KEY` and the base URL from `FANCYODDS_BASE_URL`, which defaults to the sandbox, `https://api-sandbox.fancyodds.live`. For live, set `FANCYODDS_BASE_URL=https://api.fancyodds.live` and use your `fg_live_…` key.

## The examples

| What it does | Node.js | Python | PHP | curl + jq |
|---|---|---|---|---|
| List in-play events | [list-inplay.mjs](node/list-inplay.mjs) | [list_inplay.py](python/list_inplay.py) | [list-inplay.php](php/list-inplay.php) | [list-inplay.sh](curl/list-inplay.sh) |
| One event: every market, prices decoded per format | [event-markets.mjs](node/event-markets.mjs) | [event_markets.py](python/event_markets.py) | [event-markets.php](php/event-markets.php) | [event-markets.sh](curl/event-markets.sh) |
| Live SSE stream with resume and reconnect | [stream.mjs](node/stream.mjs) | [stream.py](python/stream.py) | [stream.php](php/stream.php) | [stream.sh](curl/stream.sh) |
| Poll `/v1/changes` | [poll-changes.mjs](node/poll-changes.mjs) | [poll_changes.py](python/poll_changes.py) | [poll-changes.php](php/poll-changes.php) | [poll-changes.sh](curl/poll-changes.sh) |
| Results, in order, with a saved cursor | [results.mjs](node/results.mjs) | [results.py](python/results.py) | [results.php](php/results.php) | [results.sh](curl/results.sh) |
| Fancy / session board (Yes/No, line · rate) | [fancy-board.mjs](node/fancy-board.mjs) | [fancy_board.py](python/fancy_board.py) | [fancy-board.php](php/fancy-board.php) | [fancy-board.sh](curl/fancy-board.sh) |

The shared code is small and meant to be copied: [node/lib](node/lib), [python/odds_api.py](python/odds_api.py), [php/lib.php](php/lib.php), [curl/common.sh](curl/common.sh). It handles the key header, gzip, `429 rate_limited` with `Retry-After`, price decoding and the stream.

## Reading prices: decimal, rate, line and range

Every market has a `format`. **Read it before you use `price` or `size`**: a bookmaker rate of 13 is decimal 1.13, not 13.

Each runner has `back` and `lay` ladders, best price first, as `{"price", "size"}`:

| `format` | Used for | `price` | `size` | How to read it |
|---|---|---|---|---|
| `decimal` | Match odds, Yes/No, Odd/Even | Decimal odds | Amount available | A stake of 100 at 2.88 returns 288. |
| `rate` | Bookmaker | Profit per 100 staked | Amount available | Decimal = 1 + rate / 100. Rate 13 is 1.13; rate 625 is 7.25. |
| `line` | Fancy: runs, wickets, totals | The line | The rate | Back is **Yes**: wins if the result reaches the line. Lay is **No**: wins if it stays below. |
| `range` | Khado | First winning score | The rate | Yes only: wins if the result is one of the *width* scores from `price` upward. |

```json
{ "id": "mk_3hb7tq2wc9xzv5ne", "name": "Bookmaker", "type": "bookmaker", "format": "rate", "status": "OPEN",
  "runners": [ { "id": "rn_q3m8x2wte6kd7bpa", "name": "Pakistan", "status": "OPEN",
                 "back": [{ "price": 48, "size": 100000 }], "lay": [{ "price": 52, "size": 100000 }] } ] }
```

Back 48 here means decimal 1.48: 100 staked on Pakistan wins 48.

## Fancy and session markets: Yes and No

A fancy (session) market is a `line` market with one runner. `back` is the **Yes** side and `lay` is the **No** side; in both, `price` is the line and `size` is the rate.

```json
{ "id": "mk_juc56fmwfmqx7gag", "name": "10 over run PAK", "type": "fancy", "format": "line", "status": "OPEN",
  "runners": [ { "id": "rn_p8vd2hsn4c6xqe9w", "name": "10 over run PAK", "status": "OPEN",
                 "back": [{ "price": 61, "size": 90 }], "lay": [{ "price": 61, "size": 110 }] } ] }
```

| | No | Yes |
|---|---|---|
| 10 over run PAK | 61 · 110 | 61 · 90 |

- **Yes 100 at 61** wins 90 if PAK have 61 or more after 10 overs.
- **No 100 at 61** wins 100 if they stay below 61, and loses 110 if they reach it.

Khado markets use `range`: Yes only, from `price` upward across a width of scores. Odd/Even and similar Yes/No markets are plain `decimal`. [fancy-board](node/fancy-board.mjs) prints a whole board this way; add `--watch` to refresh it every 3 s with `If-None-Match`, which costs a `304` and no body while nothing moves.

```
Pakistan v Sri Lanka   09:12:44 UTC   5 fancy markets

Market                            No            Yes           Status
----------------------------------------------------------------------------
10 over run PAK                   61 · 110      61 · 90       BALL_RUNNING, no bets
20 over run PAK                   118 · 110     118 · 90      OPEN
Fall of 3rd wkt PAK               74 · 110      74 · 90       OPEN
10 over Khado run SL              —             45 · 90       OPEN  (khado)
```

## Market status and suspended markets

| `status` | Meaning | What to do |
|---|---|---|
| `OPEN` | Prices are live. | Take bets. |
| `SUSPENDED` | Temporarily not tradeable: a goal, a wicket, a review, or a feed check. | Prices may still be shown; **take no bets**. |
| `BALL_RUNNING` | Cricket: the ball is in play. | Take no bets until it is dead. |
| `CLOSED` | Finished. The market leaves the event shortly after; its result follows. | Stop showing it; settle on the result. |

A market can also carry `"stale": true` when its prices have stopped arriving; it is then shown as `SUSPENDED` until they flow again. Runners have their own `status` too. Every example uses the same rule:

```js
const tradeable = (market, runner) =>
  market.status === 'OPEN' && !market.stale && (!runner || runner.status === 'OPEN')
```

## Keeping a live odds stream alive

`GET /v1/stream?events=ev_a,ev_b` is a Server-Sent Events stream. On connect you get a `snapshot` of each event, then `ready`, then only changes:

| Message | Data | What to do |
|---|---|---|
| `snapshot` | A whole event, as from `/v1/events/{id}` | Store it (replace any copy you hold). |
| `ready` | | The opening snapshots are done. |
| `market-update` | `{"event", "market"}`, the whole market | **Replace** your copy of that market. Do not merge. |
| `market-remove` | `{"event", "market": "mk_…"}` | Drop the market; its result follows. |
| `event-update` | The event's name, start or state | Update the event (for example it went in play). |
| `event-remove` | `{"id"}` | Drop the event. |
| `result` | A result entry | Settle. See [Results](#results-and-settlement). |
| `reconnect` | | Close and reconnect **now**, with your last id. |
| `error` | `{"code", "message"}` | The stream closes, for example a revoked key. Do not retry blindly. |

To keep one stream running for days, each example does five things:

1. **Resume with `Last-Event-ID`.** Every message has an `id`. Keep the last one and send it back in the `Last-Event-ID` header when you reconnect: you receive exactly what you missed, results included. If it is too old to resume, you get fresh snapshots instead, so your copy is always whole. Treat the id as an opaque string.
2. **Reconnect on `reconnect`.** The server rotates every stream after about 14 minutes (840 s), and before a restart, by sending `reconnect`. Resuming loses nothing.
3. **Expect the 15-minute cut.** The edge in front of the API closes any single HTTP response at 900 s. The `reconnect` message normally comes first, but if the connection simply drops, resume with `Last-Event-ID` in the same way.
4. **Watch the heartbeat.** A `: heartbeat` comment line arrives every 15 s. If nothing at all arrives for 45 s, the connection is dead: reconnect.
5. **Back off on failure.** Honour the stream's `retry:` hint, add jitter, and stop on `400`, `401`, `403` and on an `error` message, which retrying cannot fix. A `429 too_many_streams` right after a reconnect usually means the old connection has not closed yet: wait a few seconds.

If your server falls behind, you are not sent every tick you missed, only the latest state of each market. A wire sample:

```
event: snapshot
id: 9f2c41d0.18342.17493
data: {"id":"ev_k9wtucdybikxygkh","name":"Pakistan v Sri Lanka","sport":"cricket", … ,"markets":[…]}

event: ready
id: 9f2c41d0.18342.17493
data: {"events":1}

event: market-update
id: 9f2c41d0.18347.17493
data: {"event":"ev_k9wtucdybikxygkh","market":{"id":"mk_vf86825bva46g3qq","name":"Match Odds", … }}

: heartbeat
```

The Node, Python and PHP examples parse SSE themselves in one short, commented function each, so you can see every step and need no SSE library. Sandbox keys must list event ids (up to 5); `events=all` needs a live key, so the examples pick the first in-play events for you.

## Polling instead of streaming

If you cannot hold a stream open: take a snapshot with `GET /v1/odds?events=…` (up to 50 events), keep its `next` token, and call `GET /v1/changes?since=<token>` every second or two. Each call returns the latest state of every market that changed and a new `next`. A `410 resync` means the token is too old: take a fresh snapshot and carry on from its token. See [poll-changes](node/poll-changes.mjs).

A stream is cheaper and faster: one stream replaces hundreds of requests a minute. Use REST with `Accept-Encoding: gzip` and `If-None-Match` (event snapshots carry an `ETag`) to keep polling light.

## Results and settlement

Every result is recorded in order and kept for at least 48 hours. It reaches you three ways: on your stream as `result`, listed by `GET /v1/results?since=`, and looked up by market (`/v1/markets/{id}/result`) or event (`/v1/events/{id}/results`).

| `action` | Meaning | What to do |
|---|---|---|
| `SETTLED` | The market's first result | Settle bets |
| `CORRECTED` | The result changed | Re-settle to the new result |
| `VOIDED` | The market was cancelled | Refund stakes |
| `UNSETTLED` | The result was withdrawn; a new one will follow | Hold settlement |

An entry carries a `winner` (`{"id", "name"}`), a number in `result` (line and range markets), or neither (void). A market can have several entries over time: the one with the highest `seq` is current. Page with `since=<next>` and call again at once while `more` is true; [results](node/results.mjs) saves its cursor to `.results-cursor`, so each run continues from the last.

## Sandbox limits

The sandbox, `https://api-sandbox.fancyodds.live`, carries real, current markets: prices move, markets suspend, results arrive. It is for building, not for running a site, so every `fg_test_…` key has these limits:

| Sandbox limit | Value |
|---|---|
| Odds delay | Prices are 60 seconds old. Results are not delayed. |
| Open streams | 1 at a time |
| Events per stream | 5, listed by id (`events=ev_a,ev_b`). `events=all` needs a live key. |
| Requests | 2 per second |

`GET /v1/me` shows the limits your key has. The helpers in this repo space requests 0.55 s apart and retry `429 rate_limited` after `Retry-After`, so the examples stay inside these limits. A key works only in its own environment: `fg_test_…` on the sandbox, `fg_live_…` on `https://api.fancyodds.live`.

## Errors

Errors are JSON, `{"code", "message"}`, and every response carries `X-Request-Id`: quote it when you contact us.

| Status | `code` | Meaning |
|---|---|---|
| 400 | `bad_request` | A parameter is wrong; the message says which. |
| 401 | `unauthorized` | No key, or a key we do not know. |
| 403 | `forbidden` | The IP is not on your allowlist, the key is for the other environment, or the account is suspended. |
| 404 | `not_found` | No such id, or not one of yours. |
| 410 | `resync` | Your token is too old: take a fresh snapshot. |
| 429 | `rate_limited` / `too_many_streams` / `quota_exceeded` | Too many requests, all stream slots in use, or an allowance used up. |
| 503 | `starting` / `maintenance` | Retry in a few seconds / planned maintenance. |

## Running each language

Set your key once (or copy [.env.example](.env.example) to `.env` and load it with `set -a; . ./.env; set +a`):

```bash
export FANCYODDS_KEY="fg_test_…"
# optional: export FANCYODDS_BASE_URL=https://api.fancyodds.live   (live key)
# optional: export SPORT=soccer                     (default: cricket)
```

**Node.js 18+**, no dependencies:

```bash
node node/list-inplay.mjs [sport]
node node/event-markets.mjs [ev_…]
node node/stream.mjs [ev_a,ev_b | all]
node node/poll-changes.mjs [ev_a,ev_b]
node node/results.mjs [mk_… | ev_…]
node node/fancy-board.mjs [ev_…] [--watch]
```

**Python 3.8+**, needs only `requests`:

```bash
pip install -r python/requirements.txt
python python/list_inplay.py [sport]
python python/stream.py [ev_a,ev_b | all]
python python/fancy_board.py [ev_…] [--watch]
```

**PHP 8.0+** with the curl extension:

```bash
php php/list-inplay.php [sport]
php php/stream.php [ev_a,ev_b | all]
php php/fancy-board.php [ev_…] [--watch]
```

**curl + bash**, needs `jq`. The key is passed to curl through a header file or stdin, never on the command line:

```bash
curl/list-inplay.sh [sport]
curl/stream.sh [ev_a,ev_b | all]
curl/fancy-board.sh [ev_…]
```

Or plain curl, no scripts:

```bash
curl -s --compressed -H "X-API-Key: $FANCYODDS_KEY" "https://api-sandbox.fancyodds.live/v1/events?state=inplay"
curl -N -H "X-API-Key: $FANCYODDS_KEY" "https://api-sandbox.fancyodds.live/v1/stream?events=ev_k9wtucdybikxygkh"
```

## OpenAPI spec

[`openapi.json`](openapi.json) describes every endpoint, parameter and response as OpenAPI 3.1. The same file is served at https://docs.fancyodds.live/openapi.json. Use it to generate a client, import it into an API tool, or hand it to a coding assistant.

## Postman collection

[`postman/fancyodds.postman_collection.json`](postman/fancyodds.postman_collection.json) has every endpoint, ready to send:

1. In Postman, choose **Import** and pick the file.
2. Open the collection's **Variables** and put your key in `apiKey` (in *Current value*, so it is never shared).
3. Send the requests in order. *In-play events* saves an `eventId`, *One event* saves a `marketId`, and the odds and results calls save their tokens, so each next request just works.

Your key works only from the IP addresses on its allowlist, so send from the **Postman desktop app** on an allowed machine: requests sent through Postman's cloud come from Postman's servers and are refused. *Live stream (SSE)* shows each message as it arrives; stop it to close the stream.

## Get an API key

1. Message us at **https://fancyodds.live/telegram** with the server IPs you will call from. Requests are accepted only from addresses on your allowlist.
2. We issue a sandbox key (`fg_test_…`). It is shown once; we keep only a hash, so store it safely. A lost key is replaced, not recovered.
3. Build against the sandbox with these examples and the [API reference](https://docs.fancyodds.live).
4. When you are ready, ask for a live key (`fg_live_…`) for `https://api.fancyodds.live`.

Keep keys on your servers, in an environment variable or a secret store, never in code or in a URL. More at **https://fancyodds.live**.

## License

[MIT](LICENSE). Questions about the API: https://fancyodds.live/telegram. Problems with these examples: open an issue, see [CONTRIBUTING.md](CONTRIBUTING.md).
