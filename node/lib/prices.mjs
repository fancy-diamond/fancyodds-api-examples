// Reading prices. Every market says how its prices are quoted in `format`:
//
//   decimal  match odds, Yes/No, Odd/Even   price = decimal odds, size = amount available
//   rate     bookmaker                      price = profit per 100 staked; decimal = 1 + rate / 100
//   line     fancy / session                price = the line, size = the rate; back = Yes, lay = No
//   range    khado                          price = first winning score, size = the rate; back only
//
// Always read `format` first: a bookmaker rate of 13 is decimal 1.13, not 13.

export const rateToDecimal = (rate) => 1 + rate / 100

// The decimal odds of a price, where that makes sense (decimal and rate only).
export function toDecimal(format, price) {
  if (format === 'decimal') return price
  if (format === 'rate') return rateToDecimal(price)
  return null
}

// Trade only when the market is OPEN, not stale, and the runner is OPEN.
// SUSPENDED, BALL_RUNNING, CLOSED or "stale": true all mean: take no bets.
export const tradeable = (market, runner) =>
  market.status === 'OPEN' && !market.stale && (!runner || !runner.status || runner.status === 'OPEN')

export const best = (ladder) => (ladder && ladder.length ? ladder[0] : null)

const num = (x, dp = 2) => (x === undefined || x === null ? '-' : Number(x).toFixed(dp).replace(/\.?0+$/, ''))
const pad = (s, n) => String(s).padEnd(n)

// One line per runner, decoded per the market's format.
export function describeRunner(market, runner) {
  const b = best(runner.back), l = best(runner.lay)
  switch (market.format) {
    case 'decimal':
      return `back ${b ? `${num(b.price)} x ${num(b.size)}` : '-'}  |  lay ${l ? `${num(l.price)} x ${num(l.size)}` : '-'}`
    case 'rate':
      return `back ${b ? `${b.price} (decimal ${num(rateToDecimal(b.price), 3)})` : '-'}  |  lay ${l ? `${l.price} (decimal ${num(rateToDecimal(l.price), 3)})` : '-'}`
    case 'line':
      // Lay is No, back is Yes. Each side: line · rate.
      return `No ${l ? `${l.price} · ${l.size}` : '-'}  |  Yes ${b ? `${b.price} · ${b.size}` : '-'}`
    case 'range': {
      // The docs name a width (how many scores win from `price` upward) but
      // not its field; print it when the market or runner carries `width`.
      const w = runner.width ?? market.width
      const span = b && w ? ` (wins on ${b.price} to ${b.price + w - 1})` : ''
      return `Yes from ${b ? `${b.price} · ${b.size}` : '-'}${w ? `  width ${w}` : ''}${span}`
    }
    default:
      return `unknown format "${market.format}": back ${b ? b.price : '-'} lay ${l ? l.price : '-'}`
  }
}

export function printMarket(market) {
  const flag = market.stale ? `${market.status}, stale` : market.status
  const state = tradeable(market) ? '' : '   <- no bets'
  console.log(`  [${flag}] ${market.name}  (${market.type}, ${market.format})${state}`)
  for (const r of market.runners || []) {
    const rs = r.status && r.status !== 'OPEN' ? ` [${r.status}]` : ''
    console.log(`      ${pad(r.name + rs, 28)} ${describeRunner(market, r)}`)
  }
}
