# ADR-0005: Verified spacer is the primary collapse mechanism

- Status: Accepted
- Date: 2026-07-29
- Supersedes: proposed ADR-0002
- Requirement refs: HIDE-001, MOVE-001

## Context

ADR-0002 proposed replacing the section spacer with automatic item movement
because earlier verification said the spacer did not hide items on a notched
display. A direct comparison with Ice and a live Window Server trace disproved
that premise:

- Ice collapses a section by expanding its divider/control item.
- On the built-in notched display, expanding our primary divider shifted the
  hidden lane out of the rendered menu bar while leaving the visible lane
  unchanged.
- Our verifier counted the Window Server's full-width `Menubar` backdrop as a
  user item. It therefore rejected a successful collapse and invoked an
  unreliable absolute cursor-parking fallback.

## Decision

Use the divider spacer as the only automatic collapse mechanism on notched and
non-notched displays. Snapshot the rendered, actionable items in the hidden
lanes before collapse, then require every one of those exact window IDs to
disappear from the public on-screen Window Server projection.

Exclude Window Server chrome and this app's control items from discovery and
verification. If the spacer cannot be verified, release it and remain expanded
with `hide_unavailable`; do not mutate third-party item positions.

Keep relative item movement for explicit user actions such as unhide,
reordering, or reveal-for-activation. Experimental free movement remains
opt-in.

## Consequences

- Basic collapse and reveal do not require Accessibility permission.
- Standalone visible apps remain standalone and clickable.
- The below-menu-bar panel remains the notch-safe access surface; it does not
  replace section collapse.
- A genuine verification failure is visible and fail-closed rather than
  triggering cursor synthesis.
- Private CGS discovery remains an OS-compatibility risk, while visual
  verification uses public `CGWindowListCopyWindowInfo`.

## Evidence

The scoped hardware receipt is
[`../initiatives/v0.2-production-hardening/receipts/HIDE-001.json`](../initiatives/v0.2-production-hardening/receipts/HIDE-001.json).
It covers three collapse/restore cycles on the built-in notched display. It
does not satisfy external-display or release acceptance.
