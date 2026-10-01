## Knowledge graph

This project has a knowledge graph under `graphify-out/`.

- For codebase questions, run `graphify query "<question>"` first when `graphify-out/graph.json` exists.
- Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts.
- Dirty graph files are expected after hooks or incremental updates. Skip graphify only when the task concerns stale graph output or the user asks not to use it.
- If `graphify-out/wiki/index.md` exists, use it for broad navigation. Read `GRAPH_REPORT.md` only for broad architecture reviews or when a query does not provide enough context.
- After changing code, run `graphify update .`.

## Building and running on Apple TV

The Xcode project is `_Project/Browser.xcodeproj`, and the scheme is `Browser`. Preserve the project's existing automatic signing and development-team settings.

1. Find the connected device and tvOS destination:

   ```sh
   xcrun devicectl list devices
   xcodebuild -project _Project/Browser.xcodeproj -scheme Browser -showdestinations
   ```

2. Build a signed Debug app. Replace `<XCODE_DEVICE_ID>` with the tvOS destination ID reported by Xcode:

   ```sh
   xcodebuild -project _Project/Browser.xcodeproj -scheme Browser -configuration Debug -destination 'platform=tvOS,id=<XCODE_DEVICE_ID>' -derivedDataPath /private/tmp/tvosbrowser-device-build -allowProvisioningUpdates build CODE_SIGN_STYLE=Automatic
   ```

3. Install and launch it. Replace `<COREDEVICE_ID>` with the CoreDevice identifier and `<APP_BUNDLE_ID>` with the bundle identifier configured in the Xcode target:

   ```sh
   xcrun devicectl device install app --device <COREDEVICE_ID> /private/tmp/tvosbrowser-device-build/Build/Products/Debug-appletvos/Browser.app
   xcrun devicectl device process launch --device <COREDEVICE_ID> <APP_BUNDLE_ID>
   ```

A successful build or launch does not confirm that an interaction bug is fixed. Verify the behavior on the device.

## History storage safeguards

Before changing database paths, fallback order, or history retention, inspect the actual app data container on the target device and copy the existing `BrowserHistory.sqlite` database. Do not infer its live location from simulator behavior or source-code preferences.

```sh
xcrun devicectl device info files --device <COREDEVICE_ID> --domain-type appDataContainer --domain-identifier <APP_BUNDLE_ID> --filter "Name CONTAINS 'BrowserHistory.sqlite'"
xcrun devicectl device copy from --device <COREDEVICE_ID> --domain-type appDataContainer --domain-identifier <APP_BUNDLE_ID> --source <DATABASE_PATH_FROM_DEVICE> --destination /private/tmp/tvosbrowser-history-before-change.sqlite
```

After installing a history change, visit a new page on the device and verify that it appears in **All History** and remains after relaunch. Check database row counts before and after if the UI is ambiguous. Do not add automatic age-based deletion; history is cleared only through an explicit user action. Any move to durable storage must preserve and verify the existing database on the device.

## Git policy

Do not create Git commits or push this repository. Leave changes in the working tree for the user.

## Documentation and versioning

- Write and maintain project documentation in English. Use the fork name **just-better-code version**.
- Follow [Common Changelog](https://common-changelog.org/) in `CHANGELOG.md`: `# Changelog`, newest versions first, `## VERSION - YYYY-MM-DD`, and only `Changed`, `Added`, `Removed`, `Fixed` groups in that order, omitting empty groups.
- Write each change as one unnumbered, single-line item starting with an imperative verb, explaining its user impact and ending with relevant Markdown references in parentheses. Order changes by importance, with breaking changes first and prefixed `**Breaking:**`. Merge related changes; omit reverted experiments with no effect on the resulting version.
- Keep release bodies limited to change groups and, when needed, one single-sentence notice before them. Put long explanations in linked documents; do not add roadmap, process, timeline or source-table sections to `CHANGELOG.md`.
- Keep detailed dialogue history, implementation reasoning, verification evidence and reversals in `DEVELOPMENT_HISTORY.md`; keep planned and rejected directions in `ROADMAP.md`; keep usage instructions in `USER_GUIDE.md`. Link these documents from the changelog when useful.
- Keep process and versioning rules in `AGENTS.md`, rather than mixing them into the changelog or user documentation.
- Use `major.minor.patch`: increment minor for each substantial feature and reset patch to zero; increment patch for each subsequent logical bug fix. The next fix after `2.15.22` is `2.15.23`; the next substantial feature is `2.16.0`, followed by `2.16.1` for its first fix.
- Documentation or formatting changes alone do not increment the application version. Keep Debug and Release `MARKETING_VERSION` consistent. Treat `CURRENT_PROJECT_VERSION` as a separate technical build number, not the user-facing fix number.
- Preserve the initial retrospective baseline: upstream `9b90e0e` is `2.0.0`; the initial snapshot is `2.15.22`, cataloguing 15 feature groups and 22 fix groups. These are reconstructed logical versions, not proof of separately published binaries. Historical fix IDs do not imply every fix occurred after feature 2.15.
- Distinguish commit/package dates from implementation dates in dialogue history. Do not invent release dates, Git tags, published releases or verification results. This private project's retrospective changelog has no matching release tags; explain that status in its release notice.
