<?php
// Collect results in order, never missing or repeating one.
//   php results.php           page through /v1/results from the saved cursor
//   php results.php mk_...    the current result of one market
//   php results.php ev_...    every market of one event, settled or pending
// The cursor is kept in .results-cursor, so a second run picks up where the first stopped.
require __DIR__ . '/lib.php';

const CURSOR = __DIR__ . '/.results-cursor';
// SETTLED: settle bets. CORRECTED: re-settle. VOIDED: refund. UNSETTLED: hold.
// For one market, the entry with the highest seq is the current one.
const TODO = ['SETTLED' => 'settle', 'CORRECTED' => 're-settle', 'VOIDED' => 'refund stakes', 'UNSETTLED' => 'hold settlement'];

function outcome(array $r): string
{
    if (!empty($r['winner'])) {
        return 'winner ' . $r['winner']['name'];
    }
    if (isset($r['result'])) {
        return 'result ' . $r['result'];
    }
    return 'no winner (void)';
}

run(function () use ($argv) {
    $arg = $argv[1] ?? '';
    if (strncmp($arg, 'mk_', 3) === 0) {
        $r = get_json("/v1/markets/$arg/result");
        echo "{$r['event']['name']} / {$r['market']['name']}: {$r['status']}, " . outcome($r) . (!empty($r['corrected']) ? ' (corrected)' : '') . ', seq ' . ($r['seq'] ?? '-') . "\n";
        return;
    }
    if (strncmp($arg, 'ev_', 3) === 0) {
        foreach (get_json("/v1/events/$arg/results")['markets'] as $m) {
            printf("%-8s %s%s\n", $m['status'], $m['market']['name'], $m['status'] === 'PENDING' ? '' : ': ' . outcome($m));
        }
        return;
    }

    $since = is_file(CURSOR) ? (int)trim((string)file_get_contents(CURSOR)) : 0;
    $count = 0;
    while (true) {
        try {
            $page = get_json('/v1/results', ['since' => $since, 'limit' => 500]);
        } catch (ApiError $e) {
            if ($e->status === 410) {
                echo "410 resync: cursor older than what is kept; starting from 0\n";
                $since = 0;
                continue;
            }
            throw $e;
        }
        foreach ($page['results'] as $r) {
            $count++;
            printf("#%d %-9s %s · %s / %s: %s  -> %s\n", $r['seq'], $r['action'], $r['sport'], $r['event']['name'] ?? '', $r['market']['name'] ?? '', outcome($r), TODO[$r['action']] ?? $r['action']);
        }
        $since = $page['next'];
        file_put_contents(CURSOR, (string)$since);
        if (!$page['more']) {   // while more is true, call again at once
            break;
        }
    }
    echo "$count new result entries. Cursor saved: since=$since\n";
});
