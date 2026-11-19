## Kanonfode – Kill on Sight (K-KoS) v0.4.18 — Automatic Bug Tracer and logo

### Added
- Start the local Bug Tracer automatically when its separate child addon is enabled and loaded.
- Show the K-KoS icon and group the child under K-KoS in the AddOns list.
- Keep the child enabled by default on a fresh install; users can uncheck it in the AddOns list to stop tracing.

### Preserved
- Keep the trace buffer limited to 80 in-memory events, with no names, GUIDs, guilds, chat, or SavedVariables.
- Keep all official database, SavedVariables, detection, and sync logic unchanged.
- No live in-game test was performed by the build agent.

## Kanonfode – Kill on Sight (K-KoS) v0.4.17 — Optional Bug Tracer

### Added
- Add a separate, load-on-demand `KoS-Kanonfode_Trace` child addon that records detector, Nearby, and target-alert reason codes only after the user enables tracing.
- Keep up to 80 events in memory; reports include module availability, hostile-player signals, range results, and suppression reasons, with no names, GUIDs, guilds, chat, or saved locations.
- Expose enable/disable/clear/report methods through the existing `/dump` utility without registering addon slash commands.

### Preserved
- Leave tracing off by default and store no trace data in SavedVariables.
- Keep account data, detection behavior, and sync protocol unchanged while tracing is off.
- No live in-game tracer test was performed by the build agent.

## Kanonfode – Kill on Sight (K-KoS) v0.4.16 — Movable Spy alert

### Added
- Drag the Spy-style target/stealth alert by its background to choose a screen position; save that position in the existing account-wide settings so it persists across `/reload`.
- Keep the clickable player-name area anchored to the alert frame and skip dragging during combat.

### Preserved
- Keep the alert's default position near the upper center until moved.
- Leave database lists, sync behavior and SavedVariables migration logic unchanged.
- No live in-game test was performed by the build agent.

## Kanonfode – Kill on Sight (K-KoS) v0.4.15 — Fix Notifier startup error

### Fixed
- Anchor the protected clickable button in the Spy-style “Enemy targeting you!” alert to the alert frame, not the name FontString. The invalid protected-frame anchor raised a Lua error while loading Notifier.lua, leaving `KillOnSight_Notifier` unset and causing Detector to exit before adding Nearby entries.
- Keep the alert button aligned over the name row as the alert width changes.

### Preserved
- Keep the targeting alert clickable with its existing combat-safe secure macro.
- Leave database/SavedVariables logic and Nearby range settings unchanged.
- No live in-game test was performed by the build agent.

## Kanonfode – Kill on Sight (K-KoS) v0.4.14 — Target detection fallback

### Changed
- Treat selected targets and mouseover units as high-confidence Nearby sightings so they use the expanded range.
- Check UnitIsEnemy, UnitCanAttack and UnitIsFriend independently; a negative result from one API no longer prevents positive attackability or enemy results from being considered.

### Preserved
- Keep the 2.5-second scan, Nearby settings and official database behavior unchanged.
- No live in-game test was performed.

## Kanonfode – Kill on Sight (K-KoS) v0.4.13 — Nearby range control

### Added
- Set the default Nearby range to 100 yards and add a saved Options slider from 60 to 200 yards in 10-yard steps.
- Apply the selected range to Nearby entries and their new-arrival sound; preserve the existing 1.5x range for high-confidence detections.

### Preserved
- Keep the 2.5-second nameplate scan and all official database/SavedVariables initialization behavior unchanged.
- No live in-game range test was performed; actual detection distance depends on unit data exposed by WoW Forever.

## Kanonfode – Kill on Sight (K-KoS) v0.4.12 — Clickable target alert

### Changed
- Make the player name in the target alert clickable with the same secure `/targetexact` macro pattern as Nearby rows.
- Stop the macro during combat; update the secure target action only outside combat and refresh or clear it after combat ends.
- Pre-create the secure button during addon loading so the alert can still be created during combat.

### Preserved
- Leave Database.lua and SavedVariables initialization unchanged.
- No live in-game or two-client test was performed.

## Kanonfode – Kill on Sight (K-KoS) v0.4.11 — Target alerts

### Added
- Add a Spy-style alert when a hostile enemy player visibly targets you, with a per-player 30-second cooldown and a toggle in Options.
- Show a red center alert with the enemy's class-colored name and play the bundled alert sound when the main Sound option is enabled.

### Changed
- Keep target checks active on nameplates, your selected target and focus while the Nearby window is hidden; use the existing 2.5-second scan interval.
- Retain the v0.4.10 metadata lookup, tooltip-probe throttle and periodic inspection cleanup.

### Preserved
- Leave Database.lua and SavedVariables initialization unchanged; the new option is an additive setting read through the existing settings table.
- Do not infer a positive target match when UnitIsUnit is unavailable, errors or returns a protected value.
- No live in-game or two-client test was performed.

## Kanonfode – Kill on Sight (K-KoS) v0.4.10 — Inspection cleanup and version lookup

### Changed
- Throttle unresolved specialization tooltip scans to one attempt per GUID per second, including the inspect-queue path.
- Sweep expired specialization cache entries, retry timestamps, tooltip probe timestamps and stale unit-token mappings every 60 seconds with a timer.
- Read the Options version through `C_AddOns.GetAddOnMetadata`, retain the legacy API fallback and use the release version constant when metadata is unavailable.

### Preserved
- Keep the inspect heartbeat stopped while its queue is idle; the periodic cleanup uses a low-frequency timer.
- Leave Database.lua, SavedVariables initialization, the official Player/Guild lists and sync protocol v4 unchanged.
- No live in-game or two-client test was performed.

## Kanonfode – Kill on Sight (K-KoS) v0.4.9 — Display name

### Changed
- Updated the AddOns-list title, main-window and minimap labels, and normal chat notification prefix to K-KoS branding.
- Kept the Nearby window's compact title as `K-KoS` to fit its narrower header.

### Preserved
- Kept the `KoS-Kanonfode` addon folder and TOC filename, `KillOnSightDB`, SavedVariables filename, internal Lua globals and `KOSKANON` sync prefix.
- No database migration is required. No live in-game or two-client test was performed.

## KoS-Kanonfode v0.4.8 — Reduced background UI work

### Changed
- Refresh only the visible tab and skip GUI refreshes while the main window is hidden.
- Remove the duplicate and initial hidden Stats list builds.
- Refresh the selected tab when opening it so off-screen panels stay current without background table allocation.
- Run the Retail inspect heartbeat only while inspect work is queued or pending; stop it when idle.
- Start the sync send-queue ticker only when messages are queued and stop it after the queue drains.

### Preserved
- Database, SavedVariables, class assignment and synchronization behavior remain unchanged.
- No live in-game profiler or two-client test was performed.

## KoS-Kanonfode v0.4.7 — Manual Player class selection

### Added
- Added a class dropdown for the selected Player KoS entry. The list master can set or change its class; class hints continue through the existing sync path.
- Added the installed addon version beside the KoS / Guild heading in Options.
- Registered the main window with WoW's special frames so Escape closes it.

### Preserved
- Database initialization, SavedVariables key and official Player/Guild list structure remain unchanged.
- No live in-game or two-client testing has been performed.

## KoS-Kanonfode v0.4.6 — Database and class discovery isolation

### Changed
- Rebuilt the addon runtime from the v0.4.3 source archive, preserving its Database.lua and SavedVariables logic byte for byte.
- Moved class normalization and observation lookup into a read-only ClassDiscovery module loaded after Database.lua.
- Removed the Database:AddPlayer to Comm:RequestPlayerClass callback. Comm now schedules class discovery after official changes without placing discovery inside database writes.

### Validation
- Automated Lua 5.1 tests load the actual v0.4.3, v0.4.5 and rebuilt database modules with a 7-player, 2-guild, revision-11 SavedVariables fixture.
- Initial load and simulated /reload preserve all three values. Class discovery checks are covered separately.
- Automated checks do not include live in-game or two-client testing.

## KoS-Kanonfode v0.4.3 — Sync digest repair

### Fixed
- Removed display-only class hints from the authoritative database digest. Class hints remain in FULL and DELTA payloads for recipient class icons.
- Cached the canonical digest by official database revision; invalidates after authoritative FULL/DELTA application.
- Bounded repeated digest mismatches to one FULL retry followed by a 5-minute per-peer backoff and visible status.
- Added explicit protocol-v4 mismatch handling. Mixed v3/v4 clients do not exchange official database data.

### Compatibility
- Master and members must use protocol v4 for synchronization. A v4 master identifies v3 member HELLOs and sends no official data to those clients. A v4 member with no compatible master response displays a protocol/permissions diagnostic.
- Local class observations, stats, SavedVariables identity, BG/Arena gating, Nearby and UI layout are unchanged.

## KoS-Kanonfode v0.4.2 — In-game version metadata

- Updated the WoW AddOns list title to `KoS-Kanonfode v0.4.2`.
- Updated the TOC `Version` field and internal release label to `0.4.2`.
- Standardized project release labels to numeric `vX.Y.Z` versions; no alpha labels are used.
- No gameplay, database, or synchronization protocol behavior changed in this version.

## KoS-Kanonfode v0.4.1 — Startup notice and ASCII naming

- Replaced the obsolete startup instruction `Type /kos show` with a simple localized `Loaded.` confirmation.
- Removed unused legacy `CMD_HELP` strings that advertised slash commands no longer registered by the addon.
- Rebranded the addon folder, TOC, asset paths, visible title and message prefix to the ASCII-only name `KoS-Kanonfode`.
- Preserved the SavedVariables key `KillOnSightDB`, synchronization protocol v3, Master identity, database contents, and gameplay behavior.

## KoS-Kanonfode v0.4.0 — Master, Guild Sync and taint-safe integration

- Established `Calámir Dawnsinger` as the sole Master Administrator. One addon package is used by both master and members; members receive read-only official Player KoS and Guild KoS lists.
- Added revision tracking and a bounded change journal for official Player/Guild list changes, including ADD, UPDATE and DELETE tombstones.
- Added silent private-WHISPER synchronization with HELLO, REQUEST, FULL, DELTA, SAME, ACK and NACK flow, chunking, checksums and retry handling. Member-local statistics, sightings and Options remain local.
- Added master-known class hints to FULL and DELTA updates and cleaned the member read-only Player/Guild UI.
- Removed `/kos` and `/koscomm` slash-command registrations after the supplied taint log showed KoS tainting `SlashCmdList` during Blizzard macro execution, followed by a blocked `SetRaidTarget()` call. The main window remains available from the minimap icon; Guild Sync status remains in Options.
- The taint fix and automatic Guild Sync still require live in-game regression testing across multiple clients.

# Changelog

## v0.2.1
- Fixed Player KoS Add button state after adding a targeted player.
- Add button now tracks typed names and target changes.

## KoS-Kanonfode v0.2.0 — Honor/Profile removal and simplified settings

### Removed
- Removed the Honor list, UI, portrait state, Nearby tags/actions, and Honor-only data/API paths.
- Removed profile management and profile switching from the UI and runtime API.

### Changed
- Migrates the current character's active legacy profile into one persistent account-wide `settings` table.
- Options now write directly to that settings table and are saved automatically by SavedVariables.
- Player KoS and Guild KoS remain separate. Nearby displays both the red `[KoS]` and gold `[Guild]` tags when a player matches both lists.
- Existing Nearby detection, alert scope, stats, sound playback and BG/Arena protection are retained.

### Data migration
- Player KoS, Guild KoS and non-Honor statistics are retained.
- Legacy profile containers and Honor list data are removed after migration.
- `KillOnSightDB` remains the SavedVariables key.

### Validation
- Source and ZIP checks performed. v0.2.0 still requires in-client testing; do not treat this version as runtime-verified.

---

## KoS-Kanonfode v0.1.2 — Nearby alert scope

### Added
- Added an Options setting for Nearby alert scope: **All Enemies** or **KoS List Only**.
- Existing behavior remains the default: all newly detected enemy players can trigger the Nearby arrival sound.

### Behavior preserved
- Detection, enemy observations, encounter tracking and Nearby list population continue for all detected enemy players in both modes.
- **KoS List Only** suppresses only the generic Nearby arrival sound for non-KoS players; Player KoS and Guild KoS alerts retain their existing chat/sound/flash behavior.
- The existing BG/Arena pause behavior and sound-path fix are retained.
- Existing SavedVariables are preserved; migrated settings default to **All Enemies** when no prior value exists.

---

## KoS-Kanonfode v0.1.1 — Sound playback fix

### Fixed
- Resolve bundled sound paths using the addon folder name supplied by WoW instead of hard-coded paths.
- Use a built-in raid-warning sound as a fallback when a bundled MP3 cannot be played.
- Route both Nearby detection and stealth alerts through the shared bundled-sound helper.

### Compatibility
- Retains the existing `KillOnSightDB` SavedVariables identity and all player data.
- No SavedVariables reset or migration is required.

---

## KoS-Kanonfode v0.1 — Rebrand and addon identity

- Renamed the addon folder and TOC to `KoS-Kanonfode`.
- Updated the addon title, version label, UI title, minimap tooltip title and asset paths.
- Retained the legacy `KillOnSightDB` SavedVariables key and Lua module globals to preserve existing data and internal compatibility.
- BG-safe foundation changes are documented in `BG_SAFE_FOUNDATION.md`.

---

## 3.5.7 - Stealth detection accuracy and combat-safe Nearby updates

### Fixed
- Reworked Hidden detection to prioritise observed successful Stealth, Prowl and Vanish spell casts rather than inferring stealth solely from disappearing nameplates, reducing false alerts during normal movement and mounted travel.
- Retained a short-lived cache of recently removed nameplate identities to associate late spell-cast events with the correct player.
- Prevented protected Nearby frame height changes during combat, avoiding ADDON_ACTION_BLOCKED errors from SetHeight().

### Changed
- Nearby continues recording new players while combat sorting is frozen. Rows remain within the current frame height during combat, with overflow available via scrolling.
- Deferred Nearby height updates and normal player sorting resume after combat.
- Preserved existing Hidden notifications, cooldown and Nearby integration.

### Compatibility
- No SavedVariables migration or reset required.

## 3.5.6 - Prevent death-triggered Hidden alerts

### Fixed
- Fixed false "Hidden Detected" notifications when a recently targeted stealth-capable enemy dies and their nameplate disappears.
- Added death-state checks before inferring stealth from nameplate disappearance, including cached death information and target death status where available.
- Preserved the improved Vanish/Prowl detection and existing stealth notification behavior from 3.5.5.

### Compatibility
- No SavedVariables migration or reset required.

## 3.5.5 - Improved stealth and Vanish detection

### Fixed
- Fixed missing stealth notifications when a targeted enemy Rogue vanishes or another stealth-capable enemy disappears from nameplate range.
- Cached visible nameplate player identity, class, guild and GUID before nameplate removal so detection does not rely on an already-invalid unit token.
- Improved recent-target and engagement tracking for disappearance-based hidden alerts.
- Restricted inferred hidden alerts to supported stealth-capable classes and recent observations to reduce false positives from ordinary nameplate loss.
- Preserved existing stealth notifications and Nearby hidden-state integration.

### Compatibility
- No SavedVariables migration or reset required.

## 3.5.4 - Honor overrides Guild KoS

### Changed
- Honored players are exempt from guild-wide KoS alerts even when their guild is listed in Guild KoS.
- Honor takes priority over Guild KoS for the Nearby status and target portrait, showing the green Honor dragon and `[Hon]` tag.
- Personal KoS retains highest priority: an individually KoS-listed player is still treated as KoS even when honored.
- Updating Honor membership refreshes Nearby status without requiring a reload.
- Guild KoS list membership is unchanged; the exemption applies to the honored player only.

### Compatibility
- No SavedVariables migration or reset required.

## 3.5.3 - Honor List and WoW Forever identity consolidation

### Added
- Added an independent Honor List for respected opposing-faction players, with add/remove actions from Nearby and Stats.
- Added Honor indicators in Nearby: a green dragon portrait overlay and `[Hon]` tag, without triggering KoS alerts.
- Added Stats actions to manage Honor membership and add a recorded enemy guild to Guild-KoS.
- Added localized interface text for the Honor feature across all 16 supported locales.

### Fixed
- Fixed missing Honor List class icons by passing resolved class information to the icon renderer.
- Standardized full First Last character identities across KoS, Honor, Nearby, Stats and Attackers lookups.
- Migrated legacy WoW Forever Stats identities where the old `realm` field contained the player's surname, with a separate migration backup.
- Prevented duplicate surnames from appearing when migrated full names were displayed alongside legacy surname fields.
- Prevented unsafe first-name-only Stats merges, preserving separate characters with the same given name.
- Improved full-name matching for class lookups, KoS alerts, portrait indicators, and historical PvP statistics.
- Retained existing saved data and avoided resetting encounter counts, win/loss totals, or tracked lists.

### Compatibility
- SavedVariables migration is automatic; backing up `WTF/Account/.../SavedVariables/KillOnSight.lua` before updating is recommended.
- No manual database reset is required. In-game regression testing remains recommended for legacy data.

<!-- 3.5.2 DEV: Forever legacy name/realm-as-surname schema v2 migration; new SavedVariables snapshot; safe full-identity consolidation. -->

### 3.5.2 – Full-name consolidation (development follow-up)
- Centralised canonical player-name comparison for portrait targets, Stats group filtering, guild detection and database list operations.
- Prevented first-name-only portrait matching from selecting another player with the same given name.
- Retained the existing one-time saved-data migration and its backup; no new destructive conversion is performed.
- Kept existing Honor, KoS and Guild-KoS behaviour and release version unchanged.

<!-- 3.5.2 DEV: Added one-time, backed-up WoW Forever identity migration for KoS, Honor and Stats. Conservative merge; ambiguous first-name entries retained. -->
## 3.5.2 - Honor List, Stats actions and data fixes
- KoS, Guild-KoS, and Honor management tabs now show newest additions first, with stable ordering for entries added in the same second. Existing saved entries retain their original added timestamps.

### Added
- Introduced a separate Honor List tab for tracking respected opposing-faction players independently of KoS and Guild-KoS.
- Added Nearby right-click actions to add or remove players from the Honor List.
- Added a green dragon-style indicator and a compact [Hon] tag for honoured players in Nearby.
- Persisted Honor List entries across sessions and recognised honoured players on subsequent sightings.
- Added Stats selection actions to add/remove a player from the Honor List and add their recorded guild to Guild-KoS.
- Disabled the Guild-KoS action when guild information is unavailable or the guild is already listed.

### Fixed
- Corrected PvP win/loss and encounter attribution to use full WoW Forever character identities, preventing first-name-only Stats records from receiving outcomes.
- Restored target portrait dragon overlays for KoS and Guild-KoS using WoW Forever full-name identity matching; added the green Honor portrait overlay.
- Corrected WoW Forever Stats identity handling to avoid creating duplicate records for the same First Last player.
- Added a Stats migration to consolidate existing duplicate player records when opening Stats, retaining available encounter and player information.
- Restored class colours and class icons for KoS players by resolving class data against full-name Stats records and compatible legacy name keys.
- Prevented Honor List membership alone from triggering KoS alerts.

### Localisation
- Added localisation keys for the Honor List, Nearby actions, Honoured tags/tooltips, and new Stats actions.
- Updated all 16 supported locale files for the new interface text, replacing hardcoded English strings and placeholders.

### Compatibility
- Existing KoS, Guild-KoS, Honor List, and Stats data are retained.
- Stats duplicate consolidation is applied to existing saved records; no manual reset is required.

## 3.5.1 - WoW Forever KoS detection and Nearby identity fixes

### Fixed
- Corrected KoS lookups for WoW Forever characters with First Last names so previously saved KoS players are recognised when seen again.
- Restored KoS status tags in Nearby and KoS alerts when matching players are detected.
- Fixed duplicate Nearby entries caused by different identity keys for the same character, including cases where a second entry appeared after a delayed KoS alert.
- Improved reconciliation of duplicate Nearby records while retaining existing sighting and notification state.

### Compatibility
- No SavedVariables migration required; existing KoS entries are preserved.

## 3.5.0 - Class-aware Hidden detection

### Fixed
- Restricted disappearance-based Hidden inference to Rogues, Druids, and Hunters to reduce false-positive stealth alerts from other classes.
- Prevented unknown-class enemies from triggering inferred Hidden alerts.
- Applied the class restriction to nameplate-removal detection using previously recorded class information.
- Preserved confirmed stealth-aura detection for all classes, including racial abilities such as Shadowmeld.

### Compatibility
- No SavedVariables migration required.
- Inferred Hidden detection remains heuristic and may still produce alerts when eligible classes disappear for reasons other than stealth.

## 3.4.9 - Nearby responsiveness and player announcements

### Added
- Restored the Nearby player right-click Announce submenu from 3.3.0, with Say, Party, Raid, Guild and LocalDefense destinations where available.
- Announcements include available enemy details such as name, level, class, guild, location and KoS status.

### Fixed
- Changed Nearby Announce to prefill the chat input for manual sending, avoiding protected automatic chat sends.\n- Improved Nearby refresh scheduling to reduce uneven or laggy updates.
- Improved Nearby sorting responsiveness for newly detected players while preserving safe mouseover row-order protection and combat behavior.
- Prevented duplicated class text in Nearby player tooltips when specialization information repeats the class name.
- Hardened Nearby GUID handling and sorting-cache maintenance.
- Improved Nearby refresh error visibility.

### Removed
- Removed the unused peer-to-peer Sync module, its addon-message listener, `/kos sync` command, and minimap Sync Now action.
- Removed Sync-specific menu/help translations in all supported locales.
- Stopped generating Sync change-log entries for KoS and guild edits; retained legacy SavedVariables fields for compatibility and did not erase existing KoS data.

### Compatibility
- Preserved existing KoS data, SavedVariables, and Nearby window behavior.
- Retained existing client Interface compatibility declarations pending verification against the exact game build.

## 3.4.8 - WoW Forever name, targeting and KoS list fixes

### Fixed
- Nearby list: clicking a player now targets their full First Last character name on WoW Forever.
- Nearby list: display full First Last names rather than only first names when the surname is available.
- Nearby list: resolve known surnames from Stats and refresh the displayed full name promptly when targeting or detecting a player.
- KoS Players list: show class colours and class icons using matching Stats records, including previously saved KoS entries.
- KoS Players list: display recovered First Last names for older entries where the surname was stored in the Stats realm field.
- KoS Players list: match both legacy first-name keys and newer full-name keys against Stats, including newly added players.

### Compatibility
- Preserve existing KoS entries and encounter statistics without requiring players to be removed and re-added.
- Retain existing SavedVariables and avoid changing standard realm-based behaviour on other WoW clients.

## 3.4.7 - WoW Forever Nearby targeting fix
- Fixed Nearby left-click targeting for Forever two-part character names by using the complete `First Last` name and not treating the surname as a realm.
- WoW Forever: Nearby now displays the full First Last character name, matching Stats and targeting.

## 3.4.6
- updated to work with forever

## 3.4.5

- Added _IsDisabledInstance() hard gate at top of Detector:CheckUnit and OnNameplateRemoved as defense-in-depth against instance detection leaks
- Fixed tainted boolean comparisons from UnitIsUnit, UnitIsPlayer, UnitIsEnemy, UnitIsFriend, UnitCanAttack
- Rewrote IsInPvEInstance as single pcall block to catch tainted inInstance booleans

## 3.4.4

- Fixed TOC

## 3.4.3

- Fixed _ValidPlayerGUID taint errors caused by pcall(tostring) not actually untainting secret strings; all comparisons now wrapped in pcall(function() ... end)
- Hardened remaining bare instType comparisons in Core.lua and Portrait.lua

## 3.4.2

- Fixed Detector still firing inside Delves via UNIT_AURA/spellcast events that bypassed the instance gate
- Fixed tainted string comparisons in Detector (UnitName, UnitFullName, GetGuildInfo, UnitGUID) causing "attempt to compare local 'name'" errors in protected instances

## 3.4.1

### Fixed
- Tainted GUID/instance-type comparisons in NearbyFrame causing "attempt to compare local 'guid'" errors inside Delves by wrapping IsInInstance and UnitGUID checks in pcall.

## 3.4.0

### Fixed
- `Database.lua` `_StatsKey`: cached `name:match()` result to avoid evaluating the same pattern twice (backport from Classic v3.2.5)
- `Notifier.lua`: removed excessive blank lines between `_Print` and `IsInGoblinTown`
- `NearbyFrame.lua`: fixed inconsistent nil guard on modifier key check (Shift/Ctrl/Alt) in row click handler

## 3.3.9
- Fixed bug where detector was still active in delves

## 3.3.8

### Changed
- Restructured project: all modules moved into a dedicated `Modules/` folder for cleaner organisation.
- Libraries now load via a single `Libs/embeds.xml` instead of individual file entries in the TOC.

### Fixed
- Removed redundant double-export of `_G.KillOnSight_Core` at the end of Core.lua.

### Notes
- No gameplay, SavedVariables, or API changes — this is a project-structure and housekeeping release.
- `Midnight_Init.lua` remains in the addon root as the pre-module bootstrap.
- Load order is unchanged; all global captures verified correct.

## 3.3.7
- Fix: Prevent nil realmDB errors by lazily initializing database state when accessed early (DB:GetData / DB:GetProfile)

## 3.3.6

### Fixed
- Fix: Localized the battleground/arena "Nearby disabled" notice (new L.NEARBY_DISABLED_INSTANCE)
- Fix: Prevent UI taint and ADDON_ACTION_BLOCKED errors by deferring layout updates during combat
- Fix: Safe handling of frame positioning (SetPoint / ClearAllPoints) in combat lockdown
- Improvement: Centralized deferred execution system for combat-safe UI updates

## v3.3.5

### Changed
- Midnight version is now **Retail-only (Mainline)**.
- Removed all Classic-era compatibility code and conditional branches.
- Simplified multiple modules by eliminating `IS_RETAIL` checks and fallback logic.
- Replaced dependency on Core helper with a local `IsGroupOrSelfByName()` implementation in `Midnight_Stats.lua`.

### Fixed
- Fixed **Nearby frame lock state not persisting** due to incorrect saved variable key.
- Fixed **Options UI lock checkbox** not matching actual lock variable (`nearbyFrameLocked`).
- Fixed **localization bug** caused by `GetLocale()` shadowing locale table (affected KoS/Guild-KoS detection).
- Improved **font fallback handling** to prevent empty chat messages and provide proper warning output.

## v3.3.4

### Added
- Nearby list right-click option **"Copy Name"**
- Copy popup with auto-focus and pre-selected text for quick Ctrl+C copying

### Retail
- Improved PvE instance suppression to fully disable detector inside Delves
- Prevented Retail secret-string errors when inside instanced PvE content


## v3.3.3

### Fixed
 - Update Sync funtion
 
## v3.3.2

### Added
- Nearby: New Options slider to limit --max visible rows before scrolling-- (default --20--, adjustable --5–20--).

## v3.3.1

### Fixed
- Stats --Seen-- count now increments correctly when players timeout or are re-encountered from Nearby.
- Fixed encounter resolution not firing when Nearby entries expired or were cleared.
- Resolved Lua errors:
  - GUI.lua missing `end` near EOF.
  - NearbyFrame.lua unexpected `\` symbol.
- Fixed Nearby frame incorrectly rendering certain special characters (e.g. `ß`) when using Avantgarde font.

### Improved
- Added smart font fallback for glyphs not supported by Avantgarde to keep names rendering correctly.
- Nearby display now stays visually consistent with Tooltip and Target frame name rendering.

## Version 3.3.0

### Added

- Profile system for Options (create, rename, edit).
- Account-wide KoS database shared across all characters and realms.
- Improved realm detection for cross-realm players.
- UTF-8 name handling for special characters in Nearby and Stats.
- Instant Options UI update when switching profiles.

### Improvements

- Nearby tooltip consistency with Stats data.
- Default Nearby background opacity set to 60% for new/reset profiles.
- Localization-friendly UI labels.

## Version 3.2.9

### Added

- Added Faction color to nearby tooltip and faction to stats.
- Store --realm-- in stats and display players as `Name-Realm` on Stats page.
- New --Nearby Background-- slider with profile persistence.
- Blizzard-style slider layout for Nearby Scale / Background.

### Changed

- Reworked Nearby sliders to match Name Size layout (label + value + slider).
- Converted UI text to locale keys:

  - `L.UI_NEARBY_SCALE`
  - `L.UI_NEARBY_BACKGROUND`
- Cleaned locale strings (removed debug text like “0=invisible”).

### Fixed

- Removed Realm: heading from tooltip
- Fixed font chat message spam

## Version 3.2.8

### Nearby Frame – Dynamic Auto Width

- Reworked auto-width system for improved reliability on Retail clients.
- Nearby frame now measures text using an unconstrained internal FontString to correctly expand for long entries.
- Faster, smoother width animation for more responsive resizing.
- Disabled text wrapping so entries remain on a single line.

### Combat Safety Fixes

- Fixed `ADDON_ACTION_BLOCKED` error caused by resizing the Nearby frame during combat.
- Nearby list --continues updating in combat-- so new enemies appear instantly.
- Frame resizing and re-sorting are safely deferred until combat ends.
- Pending width updates apply automatically on `PLAYER_REGEN_ENABLED`.

### Behaviour Improvements

- Prevented animation loop from attempting width updates during combat lockdown.
- Improved refresh flow so spec updates and new sightings do not cause protected calls.
- Stabilised Nearby updates in battlegrounds and high-combat environments.

### Internal

- Refactored NearbyFrame width calculation and update flow.
- Added safer handling for width animation and refresh queues.
- General cleanup to reduce taint risk on Retail UI.


## Version 3.2.7

### Nearby Frame Improvements

- Added --dynamic auto-width-- for Nearby list.
- Nearby frame now expands to fit the longest visible entry on a single line.
- Disabled text wrapping to prevent multi-line entries.
- Added smooth width animation with significantly faster expansion speed.
- Improved resize responsiveness when specs or fonts update.

### Performance & Behaviour

- Optimised width animation using dynamic speed scaling (fast expand, smooth settle).
- Reduced micro-resize jitter when multiple players update at once.
- Improved refresh handling after spec cache updates.

### Inspect / Spec Handling

- Improved inspect cache behaviour.
- Pre-warm inspect cache when Nearby entries appear (lightweight throttle).
- Prevent repeated inspect requests once a player spec is known.
- Faster tooltip spec updates.

### Font Handling

- Fixed issue where font selection required size change to apply.
- Font updates now apply instantly without blanking Nearby entries.
- Improved stability when switching fonts while players are visible.

### Internal

- Cleaned up NearbyFrame update flow.
- Reduced refresh lag caused by queued timers.
- General code refactor for smoother UI updates.

## v3.2.6

### Fixed

- Retail War Mode: specialization detection from tooltip now validates spec against the unit’s class to prevent incorrect specs appearing.
- Battlegrounds / instances: prevented “ADDON_ACTION_BLOCKED” errors caused by SetShown() during combat lockdown.
- Nearby frame visibility changes are now safely deferred until combat ends.
- Portrait.lua hardened against Blizzard protected “secret” values to prevent dragon icons appearing on all enemies in BGs.
- Disabled Nearby-related spec / portrait logic in instances where Nearby is suppressed.
- Errors caused by comparing protected GUID values in battlegrounds.
- Instance suppression now runs before GUID handling to prevent crashes.
- Nameplate spec system throwing “table index is secret” errors in BGs and instances.
- Retail inspect helpers running when Nearby should be disabled.

### Improved

- War Mode specialization detection using Blizzard tooltip data.
- Tooltip no longer shows “Inspecting...” unless an inspect is actually pending.
- War Mode specialization updates without requiring inspect requests.
- Prevented specs getting stuck on “Inspecting...”.

## v3.2.5

### Fixed

- Bug on instance enter

## v3.2.4

### Added

- Added Avantgarde font option (LibSharedMedia registration).

### Improved

- Retail inspect system rewritten for stability.
- Specs now queue from target and nameplates.
- Fixed Inspecting... getting stuck due to stale unit tokens.
- Added heartbeat + timeout recovery for inspect queue.

## 3.2.3

### Changed

- Core: consolidated GUI refresh debouncing to allow immediate and deferred updates without clobbering each other.
- Detector: added TTL cleanup for stealth/visibility state tables to prevent long-session buildup.
- Sync: switched to addon metadata version and safer percent-encoding for payload values.
- Minimap/Notifier: removed duplicate dropdown helper and unused anti-spam stub.

## 3.2.2

### Added

- Retail: pre-warm specialization inspect cache for new Nearby entries using a lightweight throttled queue.
- Retail: internal spec cache/backoff to avoid repeated inspect requests for the same player in crowded areas.

### Changed

- Retail: rewritten Inspect queue now prefers cached specs, tracks last-known unit tokens per GUID, and refreshes tooltips immediately on INSPECT_READY.

## 3.2.1

### Changed

- Retail: rewrote Nearby specialization inspection flow to update tooltips immediately when spec data is already cached.
- Retail: INSPECT_READY now updates the currently-hovered tooltip without requiring mouse-off/mouse-over.

### Fixed

- Retail: improved inspect unit resolution by caching last-known unit tokens and re-resolving via mouseover/target/focus/nameplates.
- Retail: reduced cases where spec would only appear after re-hovering.

## 3.2.0

### Added

- Nameplate scanning added for specialization inspect detection.
- Localized "Inspecting..." tooltip loading text.

### Fixed

- Combat lockdown ADDON_ACTION_BLOCKED issues with Nearby frame.
- Tooltip locale key showing instead of translated text.
- Lua syntax error in NearbyFrame.lua from nameplate inspect logic.

## 3.1.9

### Added

- Nearby tooltip now shows class (colored) and specialization (Retail via Inspect).
- Retail: automatic specialization detection for Nearby entries using INSPECT_READY.

## 3.1.8

### Added

- Added Nearby Name Font dropdown to the Options panel.
- Added Nearby Name Size slider to adjust player name text in the Nearby list.

  - Embedded LibSharedMedia-3.0 for expanded font support and automatic font detection.
- Added full localisation for:

  - Nearby name font
  - Nearby name size
  - across all supported game locales.

## 3.1.7

### Fixed

- Retail: ensure open-world win/loss stats credit when tracking targets or mouseover enemies.

## 3.1.6

### Fixed

- Retail: avoid UnitAura fallback in stealth checks to prevent AuraUtil secret-value errors.

## 3.1.5

### Fixed

- Nearby: avoid protected SetAttribute calls while clearing rows during combat.

## 3.1.4

### Fixed

- Nearby: pull full UnitFullName realm data so tooltips show realms when available.

## 3.1.3

### Fixed

- Nearby: avoid protected EnableMouse calls in combat to prevent action-blocked errors.

## 3.1.2

### Fixed

- Nearby: show realm name in the tooltip and keep click-to-target working for cross-realm players.

## 3.1.1

### Fixed

- Restored stealth inference on nameplate removal by passing the correct unit token and GUID.
- Prevented protected layout calls in combat by deferring Nearby minimal-mode layout changes until combat ends.
- Prevented protected SetHeight calls in combat by deferring Nearby frame height updates until combat ends.
- Restored Retail engagement tracking queuing for battleground win attribution.
- Allowed KoS portrait rings in battlegrounds and arenas (no suppression for KoS/Guild targets).
- Avoided Nearby menu errors by falling back when EasyMenu is unavailable.
- Fixed Nearby "Clear list" to fully reset cached entries.

## 3.1.0

### Fixed

- Removed a global `EasyMenu` shim that conflicted with other addons.
- Fixed an issue where RestedXP Guide menus were duplicated or replaced by KillOnSight entries.
- Improved compatibility with addons that rely on Blizzard’s native dropdown menu handling.

## 3.0.9 (Retail / Midnight 12.0.0)

### Stability & Crash Fixes

- Fixed multiple Retail 12.0.0 crashes caused by Blizzard returning protected
  --“secret values”-- for unit names.
- Hardened all nameplate removal handling to safely normalize unit names
  without string comparisons or method calls on protected values.
- Fixed boolean-test crashes caused by protected return values from
  `UnitTargetsPlayer()` and combat-window checks.

### Instance Safety

- Disabled Nearby / Detector processing inside:

  - Battlegrounds
  - Arenas
  - Dungeons (including Mythic+)
  - Raids
  - Scenarios
- Prevents Retail 12.x API edge cases and taint during instanced content.
- Nearby list is automatically cleared and hidden when entering instances.

### Data Handling

- Improved Retail name handling using `pcall` + `tostring` normalization.
- No changes to SavedVariables structure.
- No data loss or destructive behavior introduced.

---

## Version 3.0.8 (Retail Midnight)

- --Disable Nearby detector on Retail--

  - Prevents repeated forbidden-action errors and UI lockouts
  - Portraits no lonher show on KoS targets in BG and stats no longer log in BG due to blizzard API changes

## Version 3.0.7 (Retail Midnight Stability Update)

### 🚀 Retail (Patch 12.0 / Midnight)

- --Removed COMBAT_LOG_EVENT_UNFILTERED usage on Retail--

  - Prevents repeated forbidden-action errors and UI lockouts
  - Retail now uses unit-scoped and nameplate-based detection only
- --Nearby detection reworked for Retail--

  - Uses `NAME_PLATE_UNIT_ADDED`, target, and mouseover
  - Added --distance filtering-- to prevent far-range nameplates from flooding Nearby
- --Enemy Nameplates requirement handling--

  - When enemy nameplates are disabled:

    - Nearby switches to a limited mode (target/mouseover only)
    - A --localized warning-- is shown (includes “press V” shortcut)
  - Warning is shown --after sync messages-- for better UX
- --Attackers list disabled on Retail--

  - Removed from UI and options
  - Prevents misleading or unverifiable attacker data without combat log access

### 🛡️ Notification & Zone Rules

- --Sanctuary zones now fully respected--

  - KoS and Guild notifications no longer fire in sanctuaries

### 🌍 Localization

- Added new locale key:

  - `RETAIL_NEARBY_LIMITED_NAMEPLATES_OFF`
- Implemented across --all supported languages-- with native translations
- Removed hardcoded English warnings

### 🔧 Stability & Compatibility

- Updated embedded libraries where required to avoid BugSack/BugGrabber dependency issues

### 🧹 UI / Cleanup

- --Removed Stealth detection options from the UI--

  - Blizzard API changes in 12.0.x prevent reliable stealth detection
  - Stealth options are now fully hidden to avoid confusion

### ⚙️ Technical / Internal

- Removed reliance on deprecated or restricted combat log behavior
- Reduced unnecessary sorting and refresh work for better performance
- Improved Nearby list stability in combat-restricted environments

### Notes

Retail behavior intentionally differs from Classic-era clients due to Blizzard API changes in Patch 12.0.X Nearby detection on Retail requires --enemy nameplates enabled-- for full functionality.
Stealth alerts are not available in Retail 12.0.x due to Blizzard API restrictions.
This is a design limitation, not an addon bug.

## 3.0.6

### Fixed

- Deferred guild resolution (Spy-style): guild names now populate reliably for Nearby, Attackers, and Stats once the data becomes available (target/mouseover/nameplates)

- Attackers UI now refreshes automatically when guild info is enriched

- Fixed Nearby list click-to-target reliability, especially in battlegrounds (e.g. Alterac Valley).

  - Secure targeting attributes are now consistent and no longer desync during combat.
  - Clicking a player name now targets the correct unit reliably.

- Fixed KoS / Guild alert spam caused by repeated aura, combat log, and visibility updates.

  - KoS and Guild alerts (sound, screen flash, chat announce) now trigger --only once per player while they remain in the Nearby list--.
  - Alerts reset only after the player fully leaves the Nearby list and is seen again.

### Added

- Optional --Notes-- column on the KoS tab

  - Clickable note icon per entry (dimmed when empty)
  - Mouseover shows full note text in a wrapped, scrollable tooltip
  - Click opens a small editor to create/edit/clear notes
  - Notes are stored as `reason` in SavedVariables (Spy imports show here automatically)

### Changed

- `/kos importspy` now refreshes the KoS list immediately
- `/kos importspy` prints a message even when no new entries are found

### Notes

- Notes are metadata only and do not change KoS/Guild detection

---

## 3.0.5

### Added

- Added --Spy KoS import support--

  - New slash command: `/kos importspy`
  - Imports Kill-on-Sight entries from Spy’s SavedVariables
  - Automatically skips entries already present in KillOnSight
  - Safe to disable Spy after import
- Imported metadata (such as Spy “reason”) is stored safely and ignored by core KoS logic

### Notes

- Spy must be enabled and loaded at least once before importing
- No changes to KillOnSight KoS/Guild detection or behavior

---

## 3.0.4

### Fixed

- NPC --rare, rare elite, elite, and world boss-- targets now always display their dragon indicators
- Corrected client detection so Classic-era clients use proper target-frame handling
- Ensured Retail and Classic use appropriate visual paths without conflict

### Notes

- Player KoS and Guild behavior is unchanged
- This fix applies across Retail, Classic Era, TBC Anniversary, Wrath, and Titan-Reforged

---

## 3.0.3

### Added

- Full localization support for all major languages
- Shortened tooltip strings to prevent overflow on non-English clients
- Added TOC localization metadata

### Fixed

- Retail fallback handling for target frames
- Minor UI consistency issues across versions

---

## 3.0.2

### Fixed

- Cross-version targeting fallback logic
- Sanctuary zone handling for Nearby list
- Stability and performance improvements

---

## 3.0.1

### Added

- Retail target-frame support with safe fallbacks
- Improved stealth detection handling
- Performance optimizations and throttling improvements

