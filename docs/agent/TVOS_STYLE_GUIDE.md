# tvOS interface style guide

The user-provided photo of the tvOS Settings **General** screen on 2026-10-04 is the visual reference for **just-better-code version**. A local copy is at `.references/tvos-settings-style.jpg` when working in the user's checkout; it is ignored by Git, so the rules below must stand on their own. Use the photo for separate full-screen pages: start page, tab overview, history, favorites, and torrents. Keep the existing browser menu unchanged: its current translucency over a website already fits the desired style. The media player keeps translucent controls over video. Do not give a feature its own palette or control language. The target is a natural tvOS 27 appearance while preserving compatibility with the project's older tvOS deployment target. The photo distorts color, so match its relationships and behavior rather than sampling exact RGB values.

## Structure and materials

- Use UIKit views and standard tvOS focus behavior for app-owned UI: `UIButton`, `UITableView` or `UICollectionView`, `UIAlertController`, and system text controls. HTML belongs to websites. Migrate the current HTML new-tab page to native UI without losing remote navigation, favorites, recent visits, or their management actions.
- Use a soft, blurred blue-gray background with a restrained warm glow. This is a qualitative reference from the photo, not an exact color sample. Keep the content readable without a high-contrast patterned background.
- Use wide, softly rounded, translucent gray rows and controls at rest. The focused item becomes a luminous pale surface with dark text and icon, subtly enlarges or lifts, and returns smoothly to rest when focus moves. Let the tvOS focus engine animate transitions instead of implementing CSS hover transitions or abrupt manual jumps.
- Put controls and navigation in a restrained translucent layer above content. Use the system glass effect where available at runtime; use a dark `UIBlurEffect` with a subtle border on older tvOS versions. Do not simulate Liquid Glass with opaque white rectangles or unrelated CSS gradients.
- Use the menu's generous spacing, system font, and SF Symbols. Reserve saturated color for a meaningful state or destructive action; use neutral controls for ordinary actions.
- Let the main content use the full available screen width inside tvOS safe-area margins. Do not put whole pages in a narrow centered card; panels may group controls, but lists, grids, and content rows should expand with the screen.
- In the VLC player, keep video unobscured while controls are hidden. Show the title and status with the controls, and retain the existing inactivity and active-navigation behavior.

## Focus and legibility

- Let the tvOS focus engine move among actionable elements. Focus must remain obvious on the TV from a distance; do not rely on a mouse hover style.
- Focused controls must have dark text or icons on their light focused surface. Unfocused controls must remain readable against dark or translucent surfaces. Check both states for titles, secondary text, progress, and disabled actions.
- Keep button sizes, corner radius, label hierarchy, and safe-area spacing consistent across screens. Avoid adding a new custom button subclass or color set for a single screen when the menu pattern already serves it.
- Use compact SF Symbol actions beside the focused list row when the row needs several controls. Put them in a separate focusable column so Right moves from the row to the icons; an unfocusable `accessoryView` is not an acceptable substitute. Keep icon aspect ratios fixed and supply an accessibility label.

## Remote behavior on app-owned pages

- Center activates or confirms the focused item, like Enter. Holding Center opens context actions, like a right click, when that item has context actions.
- Play/Pause is a contextual shortcut. In All History it selects or deselects the focused visit. In Torrents it plays the focused playable file, the same as Center on that file; on a torrent row it manually starts all files. On New Tab it opens options for the focused favorite or recent visit. In a media player it toggles playback.
- Show the same action labels in help text and accessibility hints. Leave website interaction and the existing browser menu controls unchanged.

## Change workflow

- Before adding a screen, compare it with the menu and the existing history screen. Reuse an established style or add a shared appearance helper if multiple screens need the same change.
- Preserve behavior and data while changing presentation. Do not replace browser history or torrent storage as part of a visual migration.
- For UI work, describe what was changed and what was actually observed. Compilation cannot establish that focus, contrast, or glass appearance works on the TV; request the user's observation when that is required.

References: [Apple tvOS design](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos/), [focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection/), and [adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass).
