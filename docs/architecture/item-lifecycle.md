# Menu-item lifecycle

## Lifecycle

```text
discover -> identify -> classify -> place -> reveal -> activate -> verify
```

1. **Discover:** enumerate menu-item window IDs and frames on the target display.
2. **Identify:** resolve a stable identity using owner bundle, item metadata, and
   Control Center specialization when necessary.
3. **Classify:** assign visible, hidden, always-hidden, or non-manageable policy.
4. **Place:** reconcile the desired lane against the live display layout.
5. **Reveal:** project managed hidden items into inline or panel presentation.
6. **Activate:** open the selected item's menu without requiring the user to
   rediscover it in the physical bar.
7. **Verify:** observe the resulting frame/menu state and emit diagnostics.

## Current behavior

- Discovery is window-server based and read-only.
- Identity is currently `bundleID:title`, which is insufficient for repeated
  image-only Control Center items.
- Lane boundaries are the app's persisted status items.
- Inline hiding uses a spacer and is verified after reflow.
- The panel captures icons when Screen Recording is granted and otherwise uses
  text labels.
- With experimental movement disabled, panel selection expands inline rather
  than directly activating the selected item.

## Target activation contract

Panel selection MUST result in one of these explicit outcomes:

1. `activated` — the selected menu opens;
2. `permission_required` — the UI names the exact missing permission and repair;
3. `unsupported` — the item cannot be safely activated and the reason is shown;
4. `failed_recovered` — activation failed, state was restored, and diagnostics
   contain a bounded failure receipt.

Silent fallback is not an accepted outcome.

## Reconciliation invariants

- one live window maps to at most one stable item identity;
- one item belongs to one desired lane per profile;
- Control Center identity does not collapse distinct modules into one item;
- movement is bounded, observable, and rollback-aware;
- display removal never leaves cached frames authoritative;
- no activation path permanently relocates an item unless policy requires it;
- panel state is a projection, not a second source of item truth.
