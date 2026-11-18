// No stream? Take a snapshot with /v1/odds, then poll /v1/changes with its token.
//   node poll-changes.mjs [ev_a,ev_b]    (default: the first 5 events in play)
// Runs until Ctrl-C. A 410 resync means the token is too old: snapshot again.
import { ApiError, get, getJSON, inplayEventIds, run, sleep } from './lib/api.mjs'
import { describeRunner } from './lib/prices.mjs'

const POLL_MS = 2000
const book = new Map()

async function snapshot(ids) {
  const res = await getJSON('/v1/odds', { events: ids.join(',') })
  book.clear()
  for (const ev of res.events) book.set(ev.id, ev)
  if (res.missing?.length) console.log(`not available: ${res.missing.join(', ')}`)
  console.log(`snapshot: ${book.size} events, token ${res.next}`)
  return res.next
}

run(async () => {
  const ids = process.argv[2] ? process.argv[2].split(',') : await inplayEventIds(5)
  if (!ids.length) return console.log('Nothing in play right now; pass event ids: node poll-changes.mjs ev_a,ev_b')
  let stopped = false
  process.on('SIGINT', () => { stopped = true })
  process.on('SIGTERM', () => { stopped = true })

  let next = await snapshot(ids)
  while (!stopped) {
    await sleep(POLL_MS)
    try {
      const { data } = await get('/v1/changes', { since: next, events: ids.join(',') })
      for (const { type, data: d } of data.changes) {
        const ev = book.get(d.event ?? d.id)
        if (type === 'market-update' && ev) {
          const i = ev.markets.findIndex((m) => m.id === d.market.id)
          i >= 0 ? (ev.markets[i] = d.market) : ev.markets.push(d.market)
          const r = d.market.runners?.[0]
          console.log(`  ${d.market.name} [${d.market.status}]${r ? '  ' + describeRunner(d.market, r) : ''}`)
        } else if (type === 'market-remove' && ev) {
          ev.markets = ev.markets.filter((m) => m.id !== d.market)
          console.log(`  removed ${d.market}`)
        } else if (type === 'event-remove') {
          book.delete(d.id)
          console.log(`  event ended ${d.id}`)
        } else if (type === 'event-update' && ev) {
          Object.assign(ev, { ...d, markets: ev.markets })
          console.log(`  event ${d.name}: ${d.state}`)
        }
      }
      console.log(`${new Date().toISOString().slice(11, 19)} ${data.changes.length} changes, next ${data.next}`)
      next = data.next
    } catch (e) {
      if (e instanceof ApiError && e.status === 410) {
        console.log('410 resync: token too old, taking a fresh snapshot')
        next = await snapshot(ids)
      } else throw e
    }
  }
})
