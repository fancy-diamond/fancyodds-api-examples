// Fetch one event in full and print every market with its prices decoded.
//   node event-markets.mjs [ev_…]     (default: the first event in play)
import { get, inplayEventIds, run } from './lib/api.mjs'
import { printMarket } from './lib/prices.mjs'

run(async () => {
  const id = process.argv[2] || (await inplayEventIds(1))[0]
  if (!id) return console.log('Nothing in play right now; pass an event id: node event-markets.mjs ev_…')

  const { data: ev, headers } = await get('/v1/events/' + id)
  console.log(`${ev.name}  (${ev.sport}, ${ev.state}, starts ${ev.start})`)
  console.log(`${ev.markets.length} markets. ETag ${headers.get('etag') ?? '-'}; X-Resume-Token ${headers.get('x-resume-token') ?? '-'}\n`)

  // Group by type so match odds, bookmaker and fancy sit together.
  for (const type of ['match_odds', 'bookmaker', 'fancy']) {
    const list = ev.markets.filter((m) => m.type === type)
    if (!list.length) continue
    console.log(type.toUpperCase())
    list.forEach(printMarket)
    console.log()
  }
  const other = ev.markets.filter((m) => !['match_odds', 'bookmaker', 'fancy'].includes(m.type))
  if (other.length) { console.log('OTHER'); other.forEach(printMarket) }

  // Asking again with the ETag costs almost nothing while no price has moved.
  const again = await get('/v1/events/' + id, {}, headers.get('etag') ? { 'If-None-Match': headers.get('etag') } : {})
  console.log(again.status === 304 ? 'Re-fetch with If-None-Match: 304 Not Modified (nothing changed).' : `Re-fetch: ${again.status}, prices moved in between.`)
})
