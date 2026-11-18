// Collect results in order, never missing or repeating one.
//   node results.mjs              page through /v1/results from the saved cursor
//   node results.mjs mk_…         the current result of one market
//   node results.mjs ev_…         every market of one event, settled or pending
// The cursor is kept in .results-cursor, so a second run picks up where the first stopped.
import { readFileSync, writeFileSync } from 'node:fs'
import { ApiError, getJSON, run } from './lib/api.mjs'

const CURSOR = new URL('./.results-cursor', import.meta.url)
const outcome = (r) => (r.winner ? `winner ${r.winner.name}` : r.result !== undefined && r.result !== null ? `result ${r.result}` : 'no winner (void)')

// SETTLED: settle bets. CORRECTED: re-settle. VOIDED: refund. UNSETTLED: hold.
// For one market, the entry with the highest seq is the current one.
const TODO = { SETTLED: 'settle', CORRECTED: 're-settle', VOIDED: 'refund stakes', UNSETTLED: 'hold settlement' }

run(async () => {
  const arg = process.argv[2]
  if (arg?.startsWith('mk_')) {
    const r = await getJSON(`/v1/markets/${arg}/result`)
    return console.log(`${r.event.name} / ${r.market.name}: ${r.status}, ${outcome(r)}${r.corrected ? ' (corrected)' : ''}, seq ${r.seq ?? '-'}`)
  }
  if (arg?.startsWith('ev_')) {
    const r = await getJSON(`/v1/events/${arg}/results`)
    for (const m of r.markets) console.log(`${m.status.padEnd(8)} ${m.market.name}${m.status === 'PENDING' ? '' : ': ' + outcome(m)}`)
    return
  }

  let since = 0
  try { since = Number(readFileSync(CURSOR, 'utf8').trim()) || 0 } catch { /* first run */ }
  let count = 0
  for (;;) {
    let page
    try {
      page = await getJSON('/v1/results', { since, limit: 500 })
    } catch (e) {
      if (e instanceof ApiError && e.status === 410) { console.log('410 resync: cursor older than what is kept; starting from 0'); since = 0; continue }
      throw e
    }
    for (const r of page.results) {
      count++
      console.log(`#${r.seq} ${r.action.padEnd(9)} ${r.sport} · ${r.event?.name} / ${r.market?.name}: ${outcome(r)}  -> ${TODO[r.action] ?? r.action}`)
    }
    since = page.next
    writeFileSync(CURSOR, String(since))
    if (!page.more) break // while more is true, call again at once
  }
  console.log(`${count} new result entries. Cursor saved: since=${since}`)
})
