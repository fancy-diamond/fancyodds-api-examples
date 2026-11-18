<?php
// Fetch one event in full and print every market with its prices decoded.
//   php event-markets.php [ev_...]   (default: the first event in play)
require __DIR__ . '/lib.php';

run(function () use ($argv) {
    $id = $argv[1] ?? (inplay_event_ids(1)[0] ?? null);
    if (!$id) {
        echo "Nothing in play right now; pass an event id: php event-markets.php ev_...\n";
        return;
    }
    $res = api_get('/v1/events/' . $id);
    $ev = $res['data'];
    echo "{$ev['name']}  ({$ev['sport']}, {$ev['state']}, starts {$ev['start']})\n";
    echo count($ev['markets']) . ' markets. ETag ' . ($res['headers']['etag'] ?? '-') . '; X-Resume-Token ' . ($res['headers']['x-resume-token'] ?? '-') . "\n\n";

    $types = ['match_odds', 'bookmaker', 'fancy'];
    foreach ($types as $t) {
        $group = array_filter($ev['markets'], function ($m) use ($t) { return $m['type'] === $t; });
        if ($group) {
            echo strtoupper($t) . "\n";
            array_map('print_market', $group);
            echo "\n";
        }
    }
    foreach ($ev['markets'] as $m) {
        if (!in_array($m['type'], $types, true)) {
            print_market($m);
        }
    }

    // Asking again with the ETag costs almost nothing while no price has moved.
    $etag = $res['headers']['etag'] ?? null;
    $again = api_get('/v1/events/' . $id, [], $etag ? ['If-None-Match: ' . $etag] : []);
    echo $again['status'] === 304 ? "Re-fetch with If-None-Match: 304 Not Modified (nothing changed).\n"
        : "Re-fetch: {$again['status']}, prices moved in between.\n";
});
