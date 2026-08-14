# Publication readiness

Status: **public source released. Binary distribution remains blocked.**<br>
Owner: `nstranquist`<br>
Reviewed: 2026-08-14

## Verified source publication

- The public repository is
  [`nstranquist/nicos-hidden-menubar`](https://github.com/nstranquist/nicos-hidden-menubar).
- GitHub identifies the repository as public and detects the GPL-3.0 license.
- The public README, screenshot, license, and security policy return HTTP 200
  without authentication.
- The public history contains no literal local signing email or team
  identifier. The evidence gate detects those value shapes without storing the
  private values in source.
- [Public macOS CI](https://github.com/nstranquist/nicos-hidden-menubar/actions/runs/31773762948)
  passed the complete publication gate at `d72ad39`.
- The first public run exposed a Swift toolchain compatibility defect. The
  source now uses the reviewed `ScreenCaptureKit` concurrency boundary.
- GitHub Actions use exact release commits. Go dependency caching is disabled
  because this repository has no Go module dependency file.

- GPL-3.0 license, `NOTICE`, and `CONTRIBUTING.md` preserve Ice
  (`jordanbaird/Ice`) attribution and compatible terms.
- `SECURITY.md` and `CHANGELOG.md` exist at the repository root.
- Nico-owned copyright and the `nstranquist` publication identity are explicit.
- Full-history and working-tree gitleaks pass. No excluded prior-employer
  identity, domain, source, asset, or publication marker is present.
- The working-tree scan excludes only ignored build output, headless-smoke
  output, and local GitNexus analysis state. Committed source remains scanned.
- `make verify-publication` is the single repository-local gate for Swift
  tests, a formatter-debt ratchet, docs, a warnings-as-errors signed release
  build, and secret scans. The portfolio PW applies the
  owner/publication-marker policy across every candidate.
- The current suite passes 162 Swift tests.
- `make docs-check` passes 11 requirements and 24 acceptance criteria.
- The signed release build is warning-free.
- `make perf-check` enforces five-minute CPU/RSS and cold/warm reveal budgets.
  The existing receipt passes RSS and reveal budgets. Its rounded `%cpu`
  observation is superseded by the new cumulative CPU-time calculation and
  needs one user-approved visible-automation refresh.
- `make headless-smoke` passes against the real native settings window.
- Three built-in-notch collapse/restore cycles passed exact rendered-item
  verification without invoking automatic third-party movement.
- The generated screenshot was visually reviewed and copied to
  `docs/assets/preferences-window.png`. It contains no private user state.
- `docs/CASE_STUDY.md` provides recruiter-readable problem, role, decisions,
  verified results, and evidence boundaries.
- `.github/workflows/ci.yml` runs the publication gate on macOS from a
  full-history checkout.
- `make release-artifact` creates a versioned archive, checksum, and provenance
  receipt while refusing to label Apple Development or unstapled output as
  distribution-ready.
- The installed runtime is reconciled to `/Applications/NicosHiddenMenuBar.app`.
  Its stable bundle identity and CDHash match the release build. The legacy
  `NicosDev` launch agent is absent and archived for rollback. The old app
  bundle remains untouched.
- The current local closeout evidence is recorded in
  [`LOCAL-20260731.json`](initiatives/v0.2-production-hardening/receipts/LOCAL-20260731.json).
- The 2026-08-12 source-publication rerun is recorded in
  [`PUBLICATION-20260812.json`](initiatives/v0.2-production-hardening/receipts/PUBLICATION-20260812.json).

## Visible local debt

- Swift formatting is ratcheted at 469 existing findings. CI rejects increases,
  but this is not a formatting-clean claim.
- Developer ID signing, notarization, stapling, and clean-machine install are
  blocked by missing external credentials/machine evidence.
- External-display, Control Center activation, and repeated move/restore
  hardware acceptance remain open.

## Public source receipt

1. The public repository was created on 2026-08-14.
2. The sanitized `main` branch was pushed from the reviewed local tree.
3. The first public CI run exposed a hosted-toolchain defect.
4. Commit `d72ad39` fixed the defect and pinned the current action releases.
5. The complete public CI gate passed.
6. A signed-out review verified the README, image, license, and security policy.
7. Tag `v0.2.0` identifies the first public source release.

## Remaining distribution boundary

This source release does not include a downloadable application. Developer ID
signing, notarization, stapling, and clean-machine evidence remain open.

Do not describe the application as a notarized binary release until those
checks pass.
