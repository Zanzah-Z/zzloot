# Zzloot v5.0
# https://ko-fi.com/zanzah_z
Ashita v4 looter/helper for FFXI clients. 
Zzloot can lot, pass, drop, auto-load zone profiles, and show/toggle a flexible on-screen rule list.


## DISCLAIMER ##
Use at your own risk. By downloading, using, modifying, or sharing this addon, you accept full responsibility for anything that happens as a result. The author is not responsible for bans, suspensions, warnings, account actions, server enforcement, lost progress, lost items/gil, character damage, crashes, instability, data loss, or any other consequence related to using this addon.
Server rules vary. Some servers may treat parts of this addon as disallowed even if other servers do not. Use this addon only where it is allowed, and only if you are willing to accept the risk yourself.
This project is provided as-is, with no warranty, promise of safety, promise of compliance, or guarantee of compatibility with any specific server, launcher, client, ruleset, or Terms of Service.


## Commands ##


### Help
/zzl help
/zzloot help

Shows the full in-game command list minus the helper text that's in this readme.


### Master toggle
/zzl on
/zzl off

Enables or disables Zzloot.


### Lot / Pass / Drop rules
Rules use:
/zzl <rule> <action> <item or ID#>
/zzl <action> <rule> <item or ID#>

Rules:
l, lot
p, pass
d, drop

Actions:
+, add
-, remove

Examples:
/zzl p + "Valor Surcoat"
/zzl + p "Valor Surcoat"
/zzl pass add "Valor Surcoat"
/zzl l - 15093
/zzl - l 15093
/zzl d + "Fire Crystal"

`LOT` and `PASS` are mutually exclusive. Adding one replaces the other for the same item. `DROP` is independent and may exist with either `LOT` or `PASS`.


### Add rule shortcut
If the action is omitted, add is assumed:
/zzl p "Valor Surcoat"
/zzl l 15093
/zzl d "Fire Crystal"


### Remove an item from every rule list
/zzl - "Valor Surcoat"
/zzl - 12345

This removes the matching item from `LOT`, `PASS`, and `DROP` without needing to specify a rule.


### Item names, IDs, and wildcards
Single-word names can be typed bare. Multi-word names should be wrapped.
/zzl p + "Valor Surcoat"
/zzl p + <Valor Surcoat>
/zzl p + [Valor Surcoat]

Numeric item IDs work directly:
/zzl p + 15093
/zzl - 15093

Wildcard matching is supported by the item resolver:
/zzl - "Valor *"
/zzl p + "*Crystal"
/zzl d + "*Geode*"

Plain partial text is not the same as a wildcard. Use `*` when matching groups of names.


### List current rules or clear rules
/zzl lot list
/zzl pass list
/zzl drop list

/zzl lot clear
/zzl pass clear
/zzl drop clear

Short forms also work:
/zzl l list
/zzl p clear
/zzl d list


### Bulk pool commands
/zzl lotall
/zzl passall


### Clear everything
/zzl clear
/zzl clearall

Clears `LOT`, `PASS`, and `DROP`, then resets loaded profiles to the current zone default profile.


### Profiles
Profiles are stored under the character-specific Ashita config path:
config\addons\Zzloot\<Name>_<ServerId>\

Commands:
/zzl save
/zzl save <Name>
/zzl load <Name>
/zzl load <A> <B> <C>
/zzl unload <Name>
/zzl unload <A> <B> <C>

Notes:
/zzl save

Without a name saves the current zone-default `zone###.lua` profile. If multiple profiles are loaded, it still defaults to `zone###.lua` and prints a hint for named saves.

Named saves do not need `.lua`:
/zzl save DynamisGear
/zzl save DynaCurrency

writes the profile as a Lua list file.


### Auto zone-load
/zzl auto
/zzl auto on (default)
/zzl auto off

Toggles automatic loading of zone-matched profiles on the first loot event.


### Ignore zones
/zzl zone
/zzl zone +i
/zzl zone -i
/zzl zone list

`/zzl zone` prints the current ZoneId and ignore status. Ignored zones show `(ignored)` in the rule-list header.


### Rule list UI
/zzl list
/zzl list show
/zzl list hide
/zzl list toggle
/zzl list show 3-99
/zzl list sort
/zzl list sort alpha
/zzl list sort recent

UI scale and opacity:
/zzl scale 50-400
/zzl s 150
/zzl list scale 50-400

/zzl opacity 30-100
/zzl alpha 30-100
/zzl o 80
/zzl list opacity 30-100

UI controls:
[-] / [+]  minimize or restore
[x]        close
SHIFT+drag move the window

If the header/buttons go off-screen, holding `SHIFT` while not dragging for about two seconds resets the window to `x=0, y=0`.


### Delay
/zzl delay <seconds>

When `Delay > 0`, per-action delay is randomized inside the configured delay range. When unset or zero, the addon uses its default 0.5~2.0sec randomized delay.


### Misc toggles
/zzl autodrop on
/zzl autodrop off
/zzl autostack on
/zzl autostack off
/zzl verbose on
/zzl verbose off


### Reset addon settings
/zzl reset

Resets addon settings to defaults while preserving saved lists, profiles, and ignored zones.


### Special item keywords
The <item> command supports several built-in keyword groups:
pool
seals
currency
geodes
avatarites
crystals
detritus
heroism
moldy
dynad
papers

Example:
/zzl p + crystals
/zzl - pool


## Install
Place the addon folder here:
addons/zzloot/

Load in game:
/addon load zzloot
/zzl help


## Misc. Notes
- Zone auto saves and loads the last saved profile set for the current ZoneId.
- If no zone profile exists, Zzloot creates a `zone###.lua` profile for that zone, sends "Zone  Initialized" message in addon chat.
- Loading profiles/lists appends unique rules into the current zone set.
- Unloading profiles/lists removes those profile rules from the current zone set.


## UPDATES ##


### v5.0
- Zzloot updated to spam less on invalid syntax; use `/zzl help` for the full command list.
- Updated single-list adding working with any order, i.e. `/zzl p + "Item"` or `/zzl + p "Item"`.
- Updated single-list removal working with any order, i.e. `/zzl p - "Item"` or `/zzl - p "Item"`.
- Added `/zzl - "Item"` and `/zzl - ID` to remove matching items from `LOT`, `PASS`, and `DROP` at once.
- Changed `/zzl save` with multiple profiles loaded so it saves the current zone-default `zone###.lua` instead of erroring.
- Updated `LOT` / `PASS` handling so they replace each other instead of coexisting on the same item.
- Left `DROP` independent so it can coexist with `LOT` or `PASS`. 
---(Still shows 'Conflict' Error with Lot/Pass+Drop).
---(To be fixed in 6.0 GUI update).
- Reduced several missed "invalid-syntax" errors to short one-line errors. Will no longer dump the full help block.
- Updated current-pool rescan after `LOT` / `PASS` edits + validation checks.
- Updated version to `5.0` from `4.0i`.


### v4.0i
- Changed rule-list adds to enforce one active rule per item: adding an item to `LOT`, `PASS`, or `DROP` now removes stale membership from the other lists first and keeps only the new target rule.
- Fixed repeat-add behavior so same-list duplicates report `No change` instead of a misleading add count + message.
- Added per-item change messages for rules/edits, now states what item was changed to and from states.


### v4.0h
- Added a short AutoDrop wake-up state so profile/zone applies trigger one inventory-drop rescan only when AutoDrop is enabled and the Drop list is non-empty.
- Update to helper for when AutoDrop is toggled on and also after Drop-list add/remove edits.
- Added a message after adding new Drop rules while AutoDrop is off, telling the user to enable `/zzl autodrop on`.


### v4.0g
- Reassigned `/zzl d` to the Drop rule list.
- Removed the short `d` alias for delay; delay is now set only with `/zzl delay <seconds>`.
- Updated help text / command reference for new layout/changes.


### v4.0f
- Added LOT memory for the current pool instance and new rules.
- Added incoming-text rejection matching for common Rare/item-limit and inventory-full checks/fails.
- Restructured warning printouts of the incoming-text helper callback.


### v4.0e
- Changed the LOT inventory check from `> 1` free slot to `>= 1`.
- Added a pre-LOT Rare-item validation check.
- Added once-per-pool warning messages if blocked lot is skipped.


### v4.0d
- Fixed Ashita v4 loot-path crash caused by direct `GetDataManager()` calls during inventory free-slot checks/lookups.
- Switched lookups to safer helper.


### v4.0c
- Changed default RuleUI alpha ordering to sort by action column first, then item name.
- Added `/zzl clear` as a shortcut for `clearall` rather than last entry.
- Added unsaved-changes warning on zone transitions. Single-zone still quietly saves default auto-save path.


### v4.0b
- Update to RuleUI zone-transition hide: render gate added to prevent stale zone/list data remaining visible mid-zone.


### v4.0a
- Remove addon spam on runtime-state flushing for zone transitions and addon/client paths.
- Updated single-zone auto-save to include removal/clear commands.
- Fixed `/zzl save` duplicate confirmation error.
- Fixed removal feedback error.
- Hide the List/RuleUI immediately during zone transitions until the new zone/profile state loads.


### v4.0
- Updated RuleUI header/status text: `Zone Name [ZoneID]`, `(ignored)`, and item-count display.
- Reworked row alignment.
- Dead-code cleanup.
