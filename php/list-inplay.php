<?php
// List the events in play now.
//   php list-inplay.php [sport]     e.g. cricket, soccer, tennis (default: cricket)
require __DIR__ . '/lib.php';

run(function () use ($argv) {
    $sport = $argv[1] ?? default_sport();
    $me = get_json('/v1/me');
    echo "Key for {$me['client']}; sports on your plan: " . implode(', ', $me['sports']) . "\n";
    if (!empty($me['limits']['delayMs'])) {
        echo 'Prices on this key are delayed ' . ($me['limits']['delayMs'] / 1000) . " s.\n";
    }

    $events = get_json('/v1/events', ['state' => 'inplay', 'sport' => $sport])['events'];
    if (!$events) {
        echo 'Nothing in play' . ($sport ? " for $sport" : '') . " right now. Try: php list-inplay.php soccer\n";
        return;
    }
    echo "\n" . count($events) . ' in play' . ($sport ? " ($sport)" : '') . ":\n\n";
    foreach ($events as $e) {
        $age = (int)round(microtime(true) - $e['updatedAt'] / 1000);
        printf("%s  %-8s %s\n", $e['id'], $e['sport'], $e['name']);
        printf("%s  %s · %d markets · last price change %d s ago\n", str_repeat(' ', strlen($e['id'])), $e['competition']['name'] ?? '', $e['marketCount'], $age);
    }
});
