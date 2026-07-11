# Performance budgets

These are proposed v0.2 release gates. Establish repeatable measurement before
accepting the numeric targets.

| Metric | Proposed budget | Measurement window |
| --- | ---: | --- |
| Idle CPU | <= 0.1% average | 5 minutes after settling |
| Idle physical footprint | <= 30 MB | panel closed after one reveal cycle |
| Warm panel reveal | p95 <= 150 ms | cached metadata/icons |
| Cold panel shell | p95 <= 250 ms | panel visible with placeholders |
| Cold icon completion | p95 <= 750 ms | baseline item count with permission |
| Display-change reconciliation | <= 500 ms | notification to stable presentation |
| Capture cache | <= 128 items and <= 16 MB | steady state |
| Background polling | 0 periodic timers | idle state |

## Receipt shape

Performance evidence includes commit, app version, hardware, OS build, display
topology, permissions, item count, sample count, raw observations, percentile
calculation, and pass/fail result. A single `ps` sample is orientation, not a
release-grade receipt.
