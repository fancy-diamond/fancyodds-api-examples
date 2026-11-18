<?php
// No stream? Take a snapshot with /v1/odds, then poll /v1/changes with its token.
//   php poll-changes.php [ev_a,ev_b]   (default: the first 5 events in play)
// Runs until Ctrl-C. A 410 resync means the token is too old: snapshot again.
require __DIR__ . '/lib.php';

const POLL_SECONDS = 2;

function snapshot(array $ids, array &$book): string
{
    $res = get_json('/v1/odds', ['events' => implode(',', $ids)]);
    $book = [];
    foreach ($res['events'] as $ev) {
        $book[$ev['id']] = $ev;
    }
    if (!empty($res['missing'])) {
        echo 'not available: ' . implode(', ', $res['missing']) . "\n";
    }
    echo 'snapshot: ' . count($book) . " events, token {$res['next']}\n";
    return $res['next'];
}

run(function () use ($argv) {
    $ids = isset($argv[1]) ? explode(',', $argv[1]) : inplay_event_ids(5);
    if (!$ids) {
        echo "Nothing in play right now; pass event ids: php poll-changes.php ev_a,ev_b\n";
        return;
    }
    $book = [];
    $token = snapshot($ids, $book);
    while (true) {
        sleep(POLL_SECONDS);
        try {
            $res = get_json('/v1/changes', ['since' => $token, 'events' => implode(',', $ids)]);
        } catch (ApiError $e) {
            if ($e->status === 410) {
                echo "410 resync: token too old, taking a fresh snapshot\n";
                $token = snapshot($ids, $book);
                continue;
            }
            throw $e;
        }
        foreach ($res['changes'] as $c) {
            $d = $c['data'];
            $evId = $d['event'] ?? $d['id'] ?? null;
            if ($c['type'] === 'market-update' && isset($book[$evId])) {
                $m = $d['market'];
                $book[$evId]['markets'] = array_values(array_filter($book[$evId]['markets'], function ($x) use ($m) { return $x['id'] !== $m['id']; }));
                $book[$evId]['markets'][] = $m;
                $r = $m['runners'][0] ?? null;
                echo "  {$m['name']} [{$m['status']}]" . ($r ? '  ' . describe_runner($m, $r) : '') . "\n";
            } elseif ($c['type'] === 'market-remove' && isset($book[$evId])) {
                $book[$evId]['markets'] = array_values(array_filter($book[$evId]['markets'], function ($x) use ($d) { return $x['id'] !== $d['market']; }));
                echo "  removed {$d['market']}\n";
            } elseif ($c['type'] === 'event-remove') {
                unset($book[$d['id']]);
                echo "  event ended {$d['id']}\n";
            } elseif ($c['type'] === 'event-update' && isset($book[$evId])) {
                $book[$evId] = array_merge($book[$evId], $d, ['markets' => $book[$evId]['markets']]);
                echo '  event ' . ($d['name'] ?? $evId) . ': ' . ($d['state'] ?? '') . "\n";
            }
        }
        echo gmdate('H:i:s') . ' ' . count($res['changes']) . " changes, next {$res['next']}\n";
        $token = $res['next'];
    }
});
