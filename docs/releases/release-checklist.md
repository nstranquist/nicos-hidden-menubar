# Release checklist

## Source and contracts

- [ ] Release version and commit are frozen.
- [ ] Requirement states and acceptance evidence are current.
- [ ] Proposed ADRs required by the release are accepted or explicitly deferred.
- [ ] README, architecture, permissions, compatibility, and known gaps agree.
- [ ] Repository audit finds no forbidden public terms or private artifacts.

## Automated gates

- [ ] `swift test` passes on a clean macOS host.
- [ ] Release build passes with warnings treated as errors.
- [ ] Formatting and requirement/link validation pass.
- [ ] Headless settings smoke passes.
- [ ] Controller, permission, display, migration, and rollback suites pass.
- [ ] Performance budgets produce a passing receipt.

## Distribution

- [ ] Bundle version matches the release tag.
- [ ] Artifact is signed with the intended stable identity.
- [ ] Notarization succeeds and ticket is stapled.
- [ ] Artifact checksum and provenance are published.
- [ ] Clean-machine install and first-run onboarding pass.
- [ ] Screen Recording, Accessibility, and login-item flows pass.
- [ ] Upgrade from the prior release preserves configuration and marker policy.
- [ ] Uninstall and rollback instructions are verified.

## Hardware acceptance

- [ ] Built-in notched display.
- [ ] Alternate display scale.
- [ ] External display on both positive and negative global origins.
- [ ] Attach/detach and resolution change while running.
- [ ] Full-screen Space and relaunch.

## Approval

- [ ] No P0/P1 issue is hidden or mislabeled.
- [ ] Operator approves the release evidence and known gaps.
