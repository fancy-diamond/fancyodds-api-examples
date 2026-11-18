<?php
// Print a fancy / session board: each market's No and Yes, as line · rate.
//   php fancy-board.php [ev_...] [--watch]
// Default: the first cricket event in play that has fancy markets. --watch
// re-reads the event every 3 s with If-None-Match, so an unchanged board costs
// a 304 and no body.
//
// Fancy markets come in three formats:
//   line     price = the line, size = the rate. Back is Yes, lay is No.
//            Yes 100 at 91 · 90 wins 90 if the result reaches 91.
//            No 100 at 91 · 110 wins 100 if it stays below 91, else loses 110.
//   range    khado: Yes only, from `price` upward over a width of scores, size = the rate.
//   decimal  Odd/Even and similar Yes/No markets in plain decimal odds.
require __DIR__ . '/lib.php';

function pick_event(): ?string
{
    $events = get_json('/v1/events', ['sport' => 'cricket', 'state' => 'inplay'])['events'];
    foreach (array_slice($events, 0, 5) as $e) {
        foreach (get_json('/v1/events/' . $e['id'])['markets'] as $m) {
            if ($m['type'] === 'fancy') {
                return $e['id'];
            }
        }
    }
    return $events[0]['id'] ?? null;
}

function cell(?array $l): string
{
    return $l ? n($l['price']) . ' · ' . n($l['size']) : '—';
}

// str_pad counts bytes; pad by characters so "·" and "—" line up (no mbstring needed).
function pad(string $s, int $w): string
{
    return $s . str_repeat(' ', max(0, $w - preg_match_all('/./su', $s)));
}

function cut(string $s, int $n): string
{
    return implode('', array_slice(preg_split('//u', $s, -1, PREG_SPLIT_NO_EMPTY), 0, $n));
}

function board(array $ev): void
{
    $fancy = array_values(array_filter($ev['markets'], function ($m) { return $m['type'] === 'fancy'; }));
    echo "\n{$ev['name']}   " . gmdate('H:i:s', (int)($ev['updatedAt'] / 1000)) . ' UTC   ' . count($fancy) . " fancy markets\n\n";
    echo pad('Market', 34) . pad('No', 14) . pad('Yes', 14) . "Status\n" . str_repeat('-', 76) . "\n";
    foreach ($fancy as $m) {
        $r = $m['runners'][0] ?? [];
        $status = tradeable($m, $r) ? 'OPEN' : (!empty($m['stale']) ? 'SUSPENDED (stale)' : $m['status']) . ', no bets';
        $name = cut($m['name'], 33);
        if ($m['format'] === 'line') {
            echo pad($name, 34) . pad(cell($r['lay'][0] ?? null), 14) . pad(cell($r['back'][0] ?? null), 14) . "$status\n";
        } elseif ($m['format'] === 'range') {
            $w = $r['width'] ?? ($m['width'] ?? null);
            echo pad($name, 34) . pad('—', 14) . pad(cell($r['back'][0] ?? null) . ($w ? " w$w" : ''), 14) . "$status  (khado)\n";
        } else {
            foreach ($m['runners'] as $x) {
                $b = $x['back'][0] ?? null;
                echo pad(cut("{$m['name']} · {$x['name']}", 33), 34) . pad('—', 14) . pad($b ? n($b['price']) : '—', 14) . "$status  (decimal)\n";
            }
        }
    }
    foreach ($fancy as $m) {
        $r = $m['runners'][0] ?? [];
        if ($m['format'] === 'line' && tradeable($m) && isset($r['back'][0], $r['lay'][0])) {
            $y = $r['back'][0];
            $no = $r['lay'][0];
            echo "\nReading \"{$m['name']}\": Yes 100 at " . n($y['price']) . ' wins ' . n($y['size']) . ' on ' . n($y['price']) . '+ runs. '
                . 'No 100 at ' . n($no['price']) . ' wins 100 below ' . n($no['price']) . ', else loses ' . n($no['size']) . ".\n";
            break;
        }
    }
}

run(function () use ($argv) {
    $args = array_slice($argv, 1);
    $watch = in_array('--watch', $args, true);
    $ids = array_values(array_filter($args, function ($a) { return strncmp($a, 'ev_', 3) === 0; }));
    $id = $ids[0] ?? pick_event();
    if (!$id) {
        echo "No cricket in play right now; pass an event id: php fancy-board.php ev_...\n";
        return;
    }
    $etag = null;
    do {
        $res = api_get('/v1/events/' . $id, [], $etag ? ['If-None-Match: ' . $etag] : []);
        if ($res['status'] !== 304) {
            $etag = $res['headers']['etag'] ?? null;
            board($res['data']);
        }
        if ($watch) {
            sleep(3);
        }
    } while ($watch);
});
