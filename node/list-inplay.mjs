// List the events in play now.
//   node list-inplay.mjs [sport]      e.g. cricket, soccer, tennis (default: cricket)
import { getJSON, run } from './lib/api.mjs'

run(async () => {
  const sport = process.argv[2] ?? process.env.SPORT ?? 'cricket'

  const me = await getJSON('/v1/me')
  console.log(`Key for ${me.client}; sports on your plan: ${me.sports.join(', ')}`)
  if (me.limits?.delayMs) console.log(`Prices on this key are delayed ${me.limits.delayMs / 1000} s.`)

  const { events } = await getJSON('/v1/events', { state: 'inplay', sport })
  if (!events.length) return console.log(`Nothing in play${sport ? ' for ' + sport : ''} right now. Try: node list-inplay.mjs soccer`)

  console.log(`\n${events.length} in play${sport ? ' (' + sport + ')' : ''}:\n`)
  for (const e of events) {
    const age = Math.round((Date.now() - e.updatedAt) / 1000)
    console.log(`${e.id}  ${e.sport.padEnd(8)} ${e.name}`)
    console.log(`${' '.repeat(e.id.length)}  ${e.competition?.name ?? ''} · ${e.marketCount} markets · last price change ${age} s ago`)
  }
})
