# Performance budgets

These are the accepted local v0.2 performance gates.
`make perf-check PERF_ALLOW_UI_AUTOMATION=true` records a five-minute
machine-readable receipt after 12 cold/warm reveal cycles and a 15-second
settling period. The explicit flag is required because those cycles visibly
open and dismiss the live panel; notify the active Mac user before running it.

| Metric | Budget | Measurement window |
| --- | ---: | --- |
| Idle CPU | <= 0.1% average | CPU-time delta over 5 minutes after settling |
| Idle physical footprint | <= 80 MiB maximum | panel closed after reveal cycles |
| Warm panel reveal | p95 <= 150 ms | cached metadata/icons |
| Cold panel shell | p95 <= 250 ms | panel visible with placeholders |
| Cold icon completion | p95 <= 750 ms | baseline item count with permission |
| Display-change reconciliation | <= 500 ms | notification to stable presentation |
| Capture cache | <= 128 items and <= 16 MB | steady state |
| Background polling | 0 periodic timers | idle state |

The original 30 MB proposal came from the much smaller v0.1 process and was not
a realistic gate after adding the SwiftUI reveal model, ScreenCaptureKit path,
bounded cache, and diagnostics. The 80 MiB ceiling is a measured, conservative
limit over the observed roughly 67 MiB v0.2 peak; it is not a claim that memory
work is finished. A regression above 80 MiB fails the gate.

## Receipt shape

Performance evidence includes commit and dirty state, app version, hardware, OS
build, display topology, permissions, item counts, raw process/reveal
observations, percentile calculation, limitations, and pass/fail result. A
single `ps` sample is orientation, not a release-grade receipt. CPU uses the
change in `ps time` (hundredth-second cumulative process CPU) divided by elapsed
wall time; the one-decimal `%cpu` field is retained only as a diagnostic sample.
