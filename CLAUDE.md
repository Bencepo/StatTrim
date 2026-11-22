# Notes for Claude

StatTrim: hide, merge and reorder categories and stats in the character window of WoW Forever (Lua 5.1). Author and rights holder: Bencepo. All rights reserved, no open-source license.

## Layout

- `StatTrim.lua`: everything in the game.
- `Libs/`: LibStub and BencepoUI (the list window, as in the other Bencepo addons; `opts.bugUrl` gives "Report a bug"). BencepoUI must be the same file in each Bencepo addon (canonical: minor 4, Nov 2026). Change it in one repo, bump the LibStub minor, copy it to the others: two different copies with the same minor make the result depend on load order.
- `Icons/minimap.tga`: in-game icon from the Bencepo logo family. `media/logo.png`: logo for CurseForge, Wago and the website (not packaged).

## How it works

- Edit mode (gear icon above the stats panel): a checkbox and arrows on every row, right in the character window. Ben wanted this in the window itself, not in a separate list.
- Normal mode: unchecked rows are removed and the rest move up. A hidden category title lets its stats join the category above.
- Rows are identified by their visible text (`RowInfo`, `Clean`); colour codes and secret values are stripped.
- ScrollBox path is taint-safe: never touch Blizzard's data provider, only re-lay out after its `Update` (hooksecurefunc). Works in combat; layout changes that need it wait for `PLAYER_REGEN_ENABLED`.

## Rules

- English only: UI texts and descriptions, no translations, no `Notes-xxXX` in the .toc.
- Buttons instead of chat commands: the gear icon (click: edit mode, right-click: list window) and the addon menu entry open everything; the list window has Show all, Rescan list, Default order and Report a bug.
- CI runs luacheck and LuaLS with the WoW API annotations; LuaLS must report zero diagnostics or the release stops.
- Release: new version heading at the top of `CHANGELOG.md`, push to `main`; the workflow uploads to CurseForge and Wago. Test in game first.
