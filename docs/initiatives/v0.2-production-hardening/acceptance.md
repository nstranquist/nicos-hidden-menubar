# Acceptance and evidence

- Initiative status: Proposed
- Last review: 2026-07-31
- Requirement state source: [`requirements.yaml`](requirements.yaml)

## v0.1 baseline

These observations describe the starting point. They do not verify the stronger
v0.2 requirements.

| Signal | Baseline |
| --- | --- |
| Unit tests | 42 passing |
| Headless settings smoke | passing |
| Dependency cycles | 0 reported by GitNexus |
| Installed signature | valid ad-hoc signature |
| Idle CPU | 0.0% observed |
| Idle physical footprint | approximately 23.5 MB observed |
| Notched display | built-in M1 MacBook Pro panel placement observed |
| Ineffective spacer | detected and compacted from 278 to 24 points |
| External monitor | not physically verified in this initiative |
| Panel activation | incomplete when experimental movement is disabled |
| Icon capture | requires Screen Recording permission |

## Evidence contract

Every evidence entry records:

- requirement and acceptance IDs;
- evidence kind such as `test`, `command`, `hardware`, `review`, `commit`, or
  `release`;
- immutable reference: commit, CI run, release checksum, or checked-in receipt;
- observation date;
- `machine`, `os_version`, and `display_topology` for hardware claims;
- exact success signal and any residual warning.

`implemented` requires `commit` evidence, `verified` requires evidence for every
acceptance ID, and `shipped` additionally requires `release` evidence naming the
installed or distributed artifact. The validator rejects evidence attached to
an unknown acceptance ID.

## Graduation table

| Requirement | State | Blocking evidence |
| --- | --- | --- |
| ARC-001 | verified | reducer and injected service owners are covered |
| ITEM-001 | accepted | commit receipt before implemented |
| HIDE-001 | accepted | commit receipt before implemented |
| ACT-001 | accepted | Control Center hardware activation plus commit |
| MOVE-001 | accepted | repeated successful hardware move/restore plus commit |
| DSP-001 | accepted | external-display hardware matrix plus commit |
| CAP-001 | accepted | commit receipt before implemented |
| TEST-001 | accepted | clean public CI execution plus commit |
| PERF-001 | accepted | passing receipt exists; commit receipt before implemented |
| REL-001 | accepted | Developer ID notarized/stapled clean-machine artifact |
| DOC-001 | implemented | validator is committed; current working-tree updates need commit |

## Known blockers

- Developer ID and notarization credentials are external operator-owned state;
- external-display hardware is not currently attached;
- Screen Recording icon-completion evidence requires an explicit user grant;
- Control Center activation remains unobserved in the hardware matrix;
- all 31 recorded experimental placement-hide attempts failed
  `item_unobserved`; repeated hardware movement is not release-ready;
- public CI and clean-machine install cannot be claimed from this checkout;
- 469 Swift formatting findings remain under a no-regression ratchet;
- private API compatibility cannot be proven solely by unit tests.

## Current v0.2 evidence

- 162 package tests cover state, identity, activation outcomes, bounded
  movement/recovery, topology calculations, capture cache, performance
  statistics, persistence, and service boundaries.
- Three built-in-notch collapse/restore cycles verified all eight intended
  hidden-lane IDs disappeared while standalone visible items remained.
- The installed v0.2 build preserved the v0.1 configuration byte-for-byte and
  retained the same stable Apple Development signing identity.
- The five-minute v0.2 performance gate collected 61 process samples and 20
  reveal samples. Its exact machine-readable observations are in
  [`receipts/PERF-001.json`](receipts/PERF-001.json). RSS and reveal evidence
  remain valid; the rounded CPU sample is superseded and awaits a
  user-approved refresh with the CPU-time delta gate.
- `make verify-publication` gates tests, the formatter ratchet, docs evidence,
  warnings-as-errors release build, and both Git-history and working-tree
  secret scans.
- The 2026-07-31 local closeout also reconciled the installed bundle and active
  process to `com.nstranquist.nicos-hidden-menubar`, archived the legacy launch
  agent for rollback, passed `make verify-installed`, and generated a local
  versioned artifact with honest non-distribution blockers. See
  [`receipts/LOCAL-20260731.json`](receipts/LOCAL-20260731.json).
