# Changelog

## 1.2.1

- Fixed: Lua error "attempt to compare local 'lx' (a secret number value)" when the character window opens. WoW Forever sometimes hides frame positions and sizes as secret values; StatTrim now skips them instead of comparing them.

## 1.2.0

- Hidden categories/stats and custom stat order are now saved per character (`StatTrimCharDB`), so melee and caster characters keep their own setup. Existing settings from `StatTrimDB` are migrated once automatically.
- Fixed: switching tabs in the character window (Reputation, Currency, Pet) no longer triggers continuous frame scans or mistakes another tab's list for the stats panel, and the gear icon hides on other tabs.
- Fixed: closing the character window in edit mode now cleans up row controls and restores the ScrollBox when nothing is hidden or reordered; changes made in combat apply automatically once combat ends; row height stays accurate when the ScrollBox recycles rows.
- Much smoother scrolling and lower memory churn: mouse-wheel scrolling repositions cached rows directly instead of rescanning and re-sorting all stats, with O(1) rank lookups and fewer temporary tables.
- Shared settings window updated to BencepoUI 5.

## 1.1.0

- The list window has the look of the other Bencepo addons (BencepoUI): it can be dragged anywhere, remembers its place, and "Report a bug" sits in its footer.

## 1.0.6

- The list window (show/hide every stat, report a bug) opens with a right-click on the gear icon and from the addon menu at the minimap. No chat command needed.
- New button "Default order" in the list window: categories and stats back in the game's own order, hidden ones stay hidden.
- English only: the German description in the addon list is removed.

## 1.0.5

- New icon in the addon list and on the minimap button, part of the new Bencepo logo family.

## 1.0.4

- "Report a bug" button in the list window (`/stt list`): shows the link to the bug reports, ready to copy with Ctrl+C.
- Fix: stats with the same name in merged categories can each be moved with the arrows.
- Fix: when StatTrim gets switched off during combat, the stats panel is put back right after combat.
- Fix: shifted stat labels are set again when the game resets them while scrolling.
- Fix: saved positions anchored to the screen are restored completely.
- Fewer allocations while scrolling in edit mode; commands no longer error before the addon has loaded; `/stt dump` skips protected rows.
- README lists `/stattrim` and `/stt dump`.

## 1.0.3

- Brighter icon that stays readable on the round minimap button.

## 1.0.2

- New icon: gilded stat bars, one cut away, for the minimap button and the addon list.

## 1.0.1

- The stats panel is only laid out again when the game changed it, not ten times a second while the character window is open. Without any hidden or moved stats StatTrim does nothing at all.
- An error during the layout no longer stops StatTrim until a /reload.

## 1.0.0

- Hide whole categories or single stats in the character window's stats panel.
- Hide only a category's name: its stats join the category above.
- Reorder categories and stats with arrows.
- Edit mode right in the window: gear icon above the stats panel (or /stt) shows a checkbox and arrows on every row.
- Works in combat without errors: StatTrim never touches Blizzard's stat list, it only moves and fades the finished rows.
- /stt list: all categories and stats in one window. /stt reset shows everything again, /stt order restores the original order.
