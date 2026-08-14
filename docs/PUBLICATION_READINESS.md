# Publication readiness

Status: **locally cleared; publication remains human-gated**<br>
Owner: `nstranquist`<br>
Reviewed: 2026-08-12

## Cleared locally

- GPL-3.0 license, `NOTICE`, and `CONTRIBUTING.md` preserve Ice
  (`jordanbaird/Ice`) attribution and compatible terms.
- `SECURITY.md` and `CHANGELOG.md` exist at the repository root.
- Nico-owned copyright and the `nstranquist` publication identity are explicit.
- Full-history and working-tree gitleaks pass; no excluded prior-employer
  identity, domain, source, asset, or publication marker is present.
- The working-tree scan excludes only ignored build output, headless-smoke
  output, and local GitNexus analysis state; committed source remains scanned.
- `make verify-publication` is the single repository-local gate for Swift
  tests, a formatter-debt ratchet, docs, a warnings-as-errors signed release
  build, and secret scans. The portfolio PW applies the
  owner/publication-marker policy across every candidate.
- The current suite passes 162 Swift tests.
- `make docs-check` passes 11 requirements and 24 acceptance criteria.
- The signed release build is warning-free.
- `make perf-check` enforces five-minute CPU/RSS and cold/warm reveal budgets.
  The existing receipt passes RSS and reveal budgets; its rounded `%cpu`
  observation is superseded by the new cumulative CPU-time calculation and
  needs one user-approved visible-automation refresh.
- `make headless-smoke` passes against the real native settings window.
- Three built-in-notch collapse/restore cycles passed exact rendered-item
  verification without invoking automatic third-party movement.
- The generated screenshot was visually reviewed and copied to
  `docs/assets/preferences-window.png`; it contains no private user state.
- `docs/CASE_STUDY.md` provides recruiter-readable problem, role, decisions,
  verified results, and evidence boundaries.
- `.github/workflows/ci.yml` is ready locally and runs the publication gate on
  macOS from a full-history checkout; it will activate only after publication.
- `make release-artifact` creates a versioned archive, checksum, and provenance
  receipt while refusing to label Apple Development or unstapled output as
  distribution-ready.
- The installed runtime is reconciled to `/Applications/NicosHiddenMenuBar.app`:
  its stable bundle identity and CDHash match the release build, the legacy
  `NicosDev` launch agent is absent and archived for rollback, and the old app
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

## Human-gated publication steps

`github.com/nstranquist/nicos-hidden-menubar` is not live. This checklist does
not create, push, or flip that repository.

1. **Done 2026-08-12.** Reviewed README, brand SVG, and screenshot as a
   signed-out visitor would see them.
   - Replaced the committed settings image with a current Layout-tab capture
     from `make headless-smoke` (no personal menu-bar, account, or email).
   - README clone URL, Ice attribution, LICENSE/NOTICE/SECURITY/CHANGELOG
     links, and screenshot alt text now match the current UI.
   - Removed the operator-only `NicosDev` launch-agent note from the README.
   - Remaining known limit: git history still contains the redacted Apple
     Development identity in an earlier commit. No history rewrite.
2. **Create and push** the public repository. Exact local command, not run:
   ```bash
   cd ~/tools/nicos-hidden-menubar
   gh repo create nstranquist/nicos-hidden-menubar \
     --public \
     --description "Native macOS menu-bar organizer with notch-safe hide/reveal. Local-first, GPL-3.0." \
     --disable-wiki
   git push -u origin main
   gh repo edit nstranquist/nicos-hidden-menubar \
     --add-topic macos --add-topic swift --add-topic menubar \
     --add-topic gpl --add-topic local-first --add-topic oss
   ```
   Origin is already `git@github.com:nstranquist/nicos-hidden-menubar.git`.
3. Confirm the already-defined public CI passes `make verify-publication`.
4. Complete a signed-out repository review before pinning it.

No public push, visibility change, profile mutation, or hosted distribution is
authorized by this checklist.
