## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Building and running on Apple TV

The Xcode project is `_Project/Browser.xcodeproj`, and the scheme is `Browser`. The app uses automatic signing with the development team and bundle identifier already configured in the project. Preserve those local signing settings.

1. Check that the Apple TV is connected and find its identifiers:

   ```sh
   xcrun devicectl list devices
   xcodebuild -project _Project/Browser.xcodeproj -scheme Browser -showdestinations
   ```

2. Build a signed Debug app for the physical device. Replace `<XCODE_DEVICE_ID>` with the `id` from `-showdestinations` (the tvOS destination):

   ```sh
   xcodebuild -project _Project/Browser.xcodeproj -scheme Browser -configuration Debug -destination 'platform=tvOS,id=<XCODE_DEVICE_ID>' -derivedDataPath /private/tmp/tvosbrowser-device-build -allowProvisioningUpdates build CODE_SIGN_STYLE=Automatic
   ```

3. Install and launch it. Replace `<COREDEVICE_ID>` with the `Identifier` from `devicectl list devices`. The current bundle identifier is `homeTvBrovser11051991`; verify it in the project if signing settings change.

   ```sh
   xcrun devicectl device install app --device <COREDEVICE_ID> /private/tmp/tvosbrowser-device-build/Build/Products/Debug-appletvos/Browser.app
   xcrun devicectl device process launch --device <COREDEVICE_ID> homeTvBrovser11051991
   ```

This workflow successfully built, installed, and launched the app on the physical Apple TV named «Спальня» on 2026-09-28. A successful launch does not confirm that a UI bug is fixed; verify the behavior on the TV.

## Git policy

Do not create Git commits or push this repository. Leave changes in the working tree for the user.
