# StatTrim

Trim the stats panel of the character window in WoW Forever down to what you actually look at.

**Website and live demo:** https://bencepo.github.io/stattrim/

![StatTrim demo](https://bencepo.github.io/media/stattrim/demo.gif)

- **Hide categories or single stats:** a checkbox on every row.
- **Hide just a category name:** its stats stay and join the category above, so you can build one compact list.
- **Reorder:** move categories and stats up and down with arrows.
- **Edit right in the window:** click the gear icon above the stats panel. Rows you turned off are shown faded until you leave edit mode.

## Commands

- `/stt` - toggle edit mode (same as the gear icon)
- `/stt list` - all categories and stats in a separate window
- `/stt reset` - show everything again
- `/stt order` - restore the original order
- `/stt dump` - debug output of the stats panel layout (open the character window first)

`/stattrim` works the same as `/stt`.

## Combat

Forever protects combat values from addons. StatTrim never changes Blizzard's stat list, it only moves and fades the rows Blizzard has already built, so the panel keeps working in combat without errors. Scrolling the panel is done by StatTrim with the mouse wheel while it is active.


## Feedback and bug reports

Found a bug or have an idea? [Open an issue](https://github.com/Bencepo/StatTrim/issues/new/choose), it takes a minute. For bugs the Lua error text (from BugSack, or `/console scriptErrors 1`) and your StatTrim version help the most. No GitHub account? Comment on [CurseForge](https://www.curseforge.com/wow/addons/stattrim#comments). Every report gets read.

## More addons by Bencepo

All addons, live demos and the web pages: **https://bencepo.github.io**

Like the addons? Support them on Ko-fi: **https://ko-fi.com/bencepo**

- [LevelTrail](https://bencepo.github.io/leveltrail/): records your leveling run; the page shows splits, XP sources, deaths, records and a share image.
- [VendorFloor](https://bencepo.github.io/vendorfloor/): auction house sniper for finds below vendor price, below disenchant value and profitable crafts.
- [ProcFlare](https://bencepo.github.io/procflare/): big Clearcasting alert and small icons for weapon, trinket and talent procs, with melee and caster sound packs.
- [SwingCast](https://bencepo.github.io/swingcast/): spell icon, cast time, latency zone and a swing timer on the standard cast bar.
- [TransmogSweep](https://bencepo.github.io/transmogsweep/): every uncollected transmog appearance on the auction house, cheapest first; buy them top to bottom with one button.

## AI disclosure

The code was written with the help of an AI assistant (Claude). Bencepo designed the features, tests everything in game and maintains the addon.

## License

All rights reserved, see [LICENSE](LICENSE).
