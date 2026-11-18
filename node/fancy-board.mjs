// Print a fancy / session board: each market's No and Yes, as line · rate.
//   node fancy-board.mjs [ev_…] [--watch]
// Default: the first cricket event in play that has fancy markets.
// --watch re-reads the event every 3 s with If-None-Match, so an unchanged
// board costs a 304 and no body.
import { get, getJSON, run, sleep } from './lib/api.mjs'
import { tradeable } from './lib/prices.mjs'

// Fancy markets come in three formats:
//   line    price = the line, size = the rate. Back is Yes, lay is No.
//           Yes 100 at 91 · 90 wins 90 if the result reaches 91.
//           No 100 at 91 · 110 wins 100 if it stays below 91, else loses 110.
//   range   khado: Yes only, from `price` upward over a width of scores, size = the rate.
//   decimal Odd/Even and similar Yes/No markets in plain decimal odds.

async function pickEvent() {
  const { events } = await getJSON('/v1/events', { sport: 'cricket', state: 'inplay' })
  for (const e of events.slice(0, 5)) {
    const { data } = await get('/v1/events/' + e.id)
    if (data.markets.some((m) => m.type === 'fancy')) return e.id
  }
  return events[0]?.id
}

const cell = (lvl) => (lvl ? `${lvl.price} · ${lvl.size}` : '—')

function board(ev) {
  const fancy = ev.markets.filter((m) => m.type === 'fancy')
  console.log(`\n${ev.name}   ${new Date(ev.updatedAt).toISOString().slice(11, 19)} UTC   ${fancy.length} fancy markets\n`)
  console.log(`${'Market'.padEnd(34)}${'No'.padEnd(14)}${'Yes'.padEnd(14)}Status`)
  console.log('-'.repeat(76))
  for (const m of fancy) {
    const r = m.runners?.[0] ?? {}
    const status = tradeable(m, r) ? 'OPEN' : (m.stale ? 'SUSPENDED (stale)' : m.status) + ', no bets'
    if (m.format === 'line') {
      console.log(`${m.name.slice(0, 33).padEnd(34)}${cell(r.lay?.[0]).padEnd(14)}${cell(r.back?.[0]).padEnd(14)}${status}`)
    } else if (m.format === 'range') {
      const w = r.width ?? m.width
      console.log(`${m.name.slice(0, 33).padEnd(34)}${'—'.padEnd(14)}${(cell(r.back?.[0]) + (w ? ' w' + w : '')).padEnd(14)}${status}  (khado)`)
    } else {
      // decimal Yes/No style: one row per runner
      for (const x of m.runners) {
        const label = `${m.name} · ${x.name}`.slice(0, 33)
        console.log(`${label.padEnd(34)}${'—'.padEnd(14)}${(x.back?.[0] ? String(x.back[0].price) : '—').padEnd(14)}${status}  (decimal)`)
      }
    }
  }
  const open = fancy.find((m) => m.format === 'line' && tradeable(m) && m.runners?.[0]?.back?.[0] && m.runners[0].lay?.[0])
  if (open) {
    const y = open.runners[0].back[0], n = open.runners[0].lay[0]
    console.log(`\nReading "${open.name}": Yes 100 at ${y.price} wins ${y.size} on ${y.price}+ runs. ` +
      `No 100 at ${n.price} wins 100 below ${n.price}, else loses ${n.size}.`)
  }
}

run(async () => {
  const args = process.argv.slice(2)
  const watch = args.includes('--watch')
  const id = args.find((a) => a.startsWith('ev_')) || (await pickEvent())
  if (!id) return console.log('No cricket in play right now; pass an event id: node fancy-board.mjs ev_…')

  let etag = null
  for (;;) {
    const res = await get('/v1/events/' + id, {}, etag ? { 'If-None-Match': etag } : {})
    if (res.status !== 304) { etag = res.headers.get('etag'); board(res.data) }
    if (!watch) break
    await sleep(3000)
  }
})
