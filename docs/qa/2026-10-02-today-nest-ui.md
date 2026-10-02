# Today and Nest UI fixes

## Design references

- Library: https://www.figma.com/design/KMmryraXYpe4O2BTgadVjJ/Samoyed?node-id=519-1365
- Nest account: https://www.figma.com/design/KMmryraXYpe4O2BTgadVjJ/Samoyed?node-id=519-1366

Library uses the approved compact sync summary, routine rows, visible Appearance and Routine Files entries, and native navigation. The plus action opens the existing Routine import flow; mobile structural authoring remains outside the product contract. Usual Week, Planner and pending Suggestions remain reachable.

Nest uses the expanded live sync summary and groups sync/conflict/time-zone controls separately from account metadata and security. Local mode, first import, errors and time-zone changes retain their existing actions. A successful last sync does not hide current errors or blocked operations. These views do not change the Nest protocol or synchronization engine.

The six template vector assets in `Samoyed/Assets.xcassets` were downloaded from the design-context exports, without modifying their SVG geometry. Original export dimensions: cloud sync 44×44 (compact callsite 34×34), chevron 16×16, refresh 24×24, external link 18×18, palette and files 25×25. Native SF Symbols, list rows, navigation bars and tab bars remain native controls.

## Today fixes

- Solid Now icon backgrounds use a contrasting foreground in dark mode.
- Agenda fallback interleaves short Note previews with blocks and open time, and initially scrolls to the current time. Opening a Note preserves its complete editable text.
- Adjacent previous/next-day buttons clarify date navigation. Today always returns to the current date and time without opening a block inspector.
- The selected Routine describes the displayed plan's source snapshot, even when a newer date rule differs; historical plan contents are preserved.

## Validation

- Local core tests: 149 passed.
- Source commit `bbc61d2`: CI core tests, Nest SQLite/D1 contracts and unsigned iOS archive all passed: https://github.com/Cabbyte/Samoyed/actions/runs/37028976382.
- Simulator regression was interrupted by simulator service failure after 6 tests passed. The remaining 18 cases did not complete; this is not a full UI acceptance pass.
- On 2026-10-03 the user explicitly requested publishing TestFlight first and stopping simulator use. Further UI and visual acceptance is deferred to the user's iPhone 16.
- Nest UI fixtures run only in DEBUG, skip Keychain restore and network synchronization, and do not demonstrate a new production authentication or two-device synchronization acceptance run.
- Release target: `ios-v2.2.1`, using the existing signed-IPA validation and Apple upload workflow.
