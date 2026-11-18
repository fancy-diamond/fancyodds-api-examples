<?php
// Open the live stream and keep a local copy of every market current.
//   php stream.php                 the first 5 events in play (sandbox keys list up to 5 ids)
//   php stream.php ev_a,ev_b       these events
//   php stream.php all             everything on your plan (live keys only)
// Runs until Ctrl-C. Resume, reconnect and heartbeats are handled in stream() in lib.php.
require __DIR__ . '/lib.php';

$book = [];  // event id -> event, as the API sends it

function t(): string
{
    return gmdate('H:i:s');
}

run(function () use ($argv, &$book) {
    $events = $argv[1] ?? implode(',', inplay_event_ids(is_sandbox_key() ? 5 : 50));
    if ($events === '') {
        echo "Nothing in play right now; pass event ids: php stream.php ev_a,ev_b\n";
        return;
    }
    stream(base_url() . '/v1/stream?events=' . $events, function (string $type, $d, ?string $lastId) use (&$book) {
        switch ($type) {
            case 'snapshot':
                $book[$d['id']] = $d;
                echo t() . " snapshot       {$d['name']}: " . count($d['markets']) . " markets\n";
                break;
            case 'ready':
                echo t() . ' ready          ' . count($book) . " events loaded; changes from here on (last id $lastId)\n";
                break;
            case 'market-update':
                $m = $d['market'];
                if (isset($book[$d['event']])) {
                    $found = false;
                    foreach ($book[$d['event']]['markets'] as $i => $old) {
                        if ($old['id'] === $m['id']) {
                            $book[$d['event']]['markets'][$i] = $m;   // whole market: replace, never merge
                            $found = true;
                        }
                    }
                    if (!$found) {
                        $book[$d['event']]['markets'][] = $m;
                    }
                }
                $state = tradeable($m) ? 'OPEN' : (!empty($m['stale']) ? "{$m['status']}, stale" : $m['status']);
                $r = $m['runners'][0] ?? null;
                echo t() . " market-update  {$m['name']} [$state]" . ($r ? "  {$r['name']}: " . describe_runner($m, $r) : '') . "\n";
                break;
            case 'market-remove':
                if (isset($book[$d['event']])) {
                    $book[$d['event']]['markets'] = array_values(array_filter($book[$d['event']]['markets'], function ($x) use ($d) { return $x['id'] !== $d['market']; }));
                }
                echo t() . " market-remove  {$d['market']} (its result follows)\n";
                break;
            case 'event-update':
                $book[$d['id']] = array_merge($book[$d['id']] ?? [], $d, ['markets' => $book[$d['id']]['markets'] ?? []]);
                echo t() . ' event-update   ' . ($d['name'] ?? $d['id']) . ': ' . ($d['state'] ?? '') . "\n";
                break;
            case 'event-remove':
                unset($book[$d['id']]);
                echo t() . " event-remove   {$d['id']}\n";
                break;
            case 'result':
                $what = isset($d['winner']) ? 'winner ' . $d['winner']['name'] : (isset($d['result']) ? 'result ' . $d['result'] : 'void');
                echo t() . " result         #{$d['seq']} {$d['action']} {$d['market']['name']}: $what\n";
                break;
            default:
                echo t() . " $type\n";
        }
    });
});
