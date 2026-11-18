// Open the live stream and keep a local copy of every market current.
//   node stream.mjs                    the first 5 events in play (sandbox keys list up to 5 ids)
//   node stream.mjs ev_a,ev_b          these events
//   node stream.mjs all                everything on your plan (live keys only)
// Runs until Ctrl-C. Resume, reconnect and heartbeats are handled in lib/sse.mjs.
import { BASE, inplayEventIds, isSandboxKey, run } from './lib/api.mjs'
import { stream } from './lib/sse.mjs'
import { describeRunner, tradeable } from './lib/prices.mjs'

const book = new Map() // event id -> event, as the API sends it

function upsertMarket(eventId, market) {
  const ev = book.get(eventId)
  if (!ev) return
  const i = ev.markets.findIndex((m) => m.id === market.id)
  if (i >= 0) ev.markets[i] = market // a market-update is the whole market: replace, never merge
  else ev.markets.push(market)
}

function line(market) {
  const r = market.runners?.[0]
  const state = tradeable(market) ? 'OPEN' : market.stale ? `${market.status}, stale` : market.status
  return `${market.name} [${state}]${r ? '  ' + r.name + ': ' + describeRunner(market, r) : ''}`
}

run(async () => {
  let events = process.argv[2]
  if (!events) {
    const ids = await inplayEventIds(isSandboxKey() ? 5 : 50)
    if (!ids.length) return console.log('Nothing in play right now; pass event ids: node stream.mjs ev_a,ev_b')
    events = ids.join(',')
  }
  const url = `${BASE}/v1/stream?events=${encodeURIComponent(events).replace(/%2C/g, ',')}`
  const stop = new AbortController()
  process.on('SIGINT', () => stop.abort())
  process.on('SIGTERM', () => stop.abort())
  const t = () => new Date().toISOString().slice(11, 19)

  await stream(url, (type, data, id) => {
    switch (type) {
      case 'snapshot':
        book.set(data.id, data)
        console.log(`${t()} snapshot       ${data.name}: ${data.markets.length} markets`)
        break
      case 'ready':
        console.log(`${t()} ready          ${book.size} events loaded; changes from here on (last id ${id})`)
        break
      case 'market-update':
        upsertMarket(data.event, data.market)
        console.log(`${t()} market-update  ${line(data.market)}`)
        break
      case 'market-remove': {
        const ev = book.get(data.event)
        if (ev) ev.markets = ev.markets.filter((m) => m.id !== data.market)
        console.log(`${t()} market-remove  ${data.market} (its result follows)`)
        break
      }
      case 'event-update':
        book.set(data.id, { ...book.get(data.id), ...data, markets: book.get(data.id)?.markets ?? [] })
        console.log(`${t()} event-update   ${data.name}: ${data.state}`)
        break
      case 'event-remove':
        book.delete(data.id)
        console.log(`${t()} event-remove   ${data.id}`)
        break
      case 'result': {
        const what = data.winner ? 'winner ' + data.winner.name : data.result !== undefined ? 'result ' + data.result : 'void'
        console.log(`${t()} result         #${data.seq} ${data.action} ${data.market?.name}: ${what}`)
        break
      }
      default:
        console.log(`${t()} ${type}`)
    }
  }, { signal: stop.signal, onStatus: (s) => console.error(`${t()} [stream] ${s}`) })
  console.log(`Stopped. Holding ${book.size} events.`)
})
