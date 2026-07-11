# Acceptance and evidence

- Initiative status: Proposed
- Last baseline observation: 2026-07-11
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
| ARC-001 | proposed | state-machine and structural coverage |
| ITEM-001 | proposed | identity fixtures and migration |
| ACT-001 | proposed | direct activation tests and hardware smoke |
| MOVE-001 | proposed | retries, rollback, and owner matrix |
| DSP-001 | proposed | automated topology plus external display |
| CAP-001 | proposed | incremental cache and latency evidence |
| TEST-001 | proposed | integration suite on CI |
| PERF-001 | proposed | machine-readable budgets and baseline receipt |
| REL-001 | proposed | CI plus signed/notarized clean-machine artifact |
| DOC-001 | proposed | schema/link validation and review |

## Known blockers

- stable signing credentials are external operator-owned state;
- external-display hardware is not currently attached;
- Accessibility and Screen Recording evidence require explicit user grants;
- private API compatibility cannot be proven solely by unit tests.
