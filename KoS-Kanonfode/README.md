# Kanonfode – Kill on Sight (K-KoS) v0.4.18

### Author: Kanonfode

K-KoS is the Kanonfode-maintained version of Kill on Sight: Forever. It preserves the original PvP-awareness structure: Nearby detects hostile players independently of the Player KoS and Guild KoS lists, while those lists provide additional identification and priority alerts.

## Features

- **Player KoS** — official individual-player list, maintained by the Master Administrator.
- **Guild KoS** — official guild list, maintained separately from Player KoS.
- **Nearby** — detects and displays hostile players whether or not they are on either KoS list.
  - Player KoS uses a red `[KoS]` tag.
  - Guild KoS uses a gold `[Guild]` tag.
  - Both tags appear when a player matches both lists.
- **Nearby alert scope** — `All Enemies` or `KoS List Only`; this filters the generic Nearby arrival sound only, not detection.
- **Nearby range** — adjustable from 60 to 200 yards; defaults to 100. High-confidence threats retain the existing 1.5x extension.
- **Notifications** — chat, screen flash, sound and stealth-detection alerts.
- **Targeting alert** — Spy-style red alert and sound when a visible hostile player starts targeting you; click the name to target them when combat lockdown permits it.
- **Statistics** — first seen, last seen, seen count, wins and losses.
- **Options** — one automatically saved configuration; no profile manager.
- **Battleground/Arena protection** — KoS activity pauses inside Battlegrounds and Arenas and resumes after leaving.
- **Guild Sync** — automatic, silent synchronization of official Player/Guild lists using private addon WHISPER messages.
- **Manual class assignment** — the list master can select a Player KoS entry and set its class.
- **Escape closes the main window**.
- **Options version label** — shows the installed addon version beside KoS / Guild.
- **Bug Tracer** — a separate child addon beneath K-KoS. It starts automatically while enabled in WoW's AddOns list and can be disabled there.

## Master and members

`Calámir Dawnsinger` is the sole Master Administrator. The same addon package is used by everyone: the master can manage the official lists, while other guild members receive read-only copies. Member-local statistics, observations and Options remain local.

## Opening KoS

Use the K-KoS minimap icon (left-click) to open or close the main window. The Options tab displays Guild Sync status. The addons intentionally register **no slash commands**, to avoid taint propagation through WoW's macro/chat parser.

## Optional Bug Tracer

The `KoS-Kanonfode_Trace` child addon appears under K-KoS in the AddOns list with the K-KoS logo. It is enabled by default on a fresh install and starts tracing automatically when the game loads it. To turn tracing off, uncheck the Bug Tracer row in the AddOns list and reload the UI. WoW remembers that choice. Re-enabling the row starts tracing again at the next login or reload.

1. Reproduce the issue.
2. Get the report: `/dump KillOnSight_Trace:Report()`
3. Stop tracing for the current session: `/dump KillOnSight_Trace:Disable()`
4. Clear its in-memory report: `/dump KillOnSight_Trace:Clear()`

The tracer uses a small in-memory buffer of at most 80 recent events; it is lost on `/reload` or logout. It records module state, decision reasons, and range/API booleans, but no player names, GUIDs, guilds, chat, or saved location. Share the report before reloading. Unchecking the Bug Tracer row prevents its code from loading.

## Installation

Extract both folders from the ZIP into the WoW AddOns directory. The final paths must be `Interface/AddOns/KoS-Kanonfode/` and `Interface/AddOns/KoS-Kanonfode_Trace/`. Remove or disable the old `KillOnSight` and any previous `KoS-Kanonfode` folder before replacing it.

## SavedVariables compatibility

The legacy SavedVariables key `KillOnSightDB` and internal Lua namespace remain unchanged. Back up `WTF/Account/<account>/SavedVariables/KoS-Kanonfode.lua` before updating. Do not delete the WTF folder or SavedVariables.


## v0.4.3 — Sync digest repair

- Official database digest excludes display-only class hints; class hints remain in FULL/DELTA payloads.
- Digest is cached by official revision and invalidated after an authoritative snapshot or delta is applied. Local stats and class observations do not affect the digest.
- Repeated digest mismatches trigger one FULL retry, then a 5-minute per-peer backoff with visible sync status.
- Sync protocol is v4. Mixed v3/v4 clients do not exchange official database data.

## Current validation notes

- v0.4.18 starts the Bug Tracer automatically when its enabled child addon loads, shows the K-KoS logo beside it, and keeps its bounded diagnostics local and in memory.
- v0.4.17 adds the separate Bug Tracer child addon with an 80-event in-memory ring buffer, no player identifiers/chat, and no slash-command registration.
- v0.4.16 lets you drag the Spy-style alert frame to a preferred screen position and saves that position across reloads. Drag by the alert background; the clickable name area remains a target button.
- v0.4.15 anchors the protected clickable target-alert button to its parent frame instead of a FontString region, preventing a load-time UI error that stopped Notifier and Nearby detection from initializing.
- v0.4.14 treats a selected target or mouseover as a high-confidence Nearby sighting and checks enemy, attackable and friendly unit flags independently to handle transient or inconsistent API results.
- v0.4.13 raises the default Nearby range to 100 yards and adds a saved 60–200-yard slider in Options. The setting controls Nearby entries and their arrival sound; high-confidence detections retain the 1.5x range. Actual range depends on units exposed by WoW Forever and needs in-game testing.
- v0.4.12 makes the target-alert name clickable using the same secure target macro as Nearby rows; target selection remains blocked during combat lockdown.
- v0.4.11 adds a throttled Spy-style alert when a hostile player targets you; the scan uses the existing 2.5-second nameplate pass and continues when Nearby is hidden.
- v0.4.10 throttles failed specialization tooltip probes, periodically clears stale inspect metadata on a 60-second timer, and reads TOC version metadata through the current `C_AddOns` API with a matching release-version fallback.
- v0.4.9 updates the display brand to Kanonfode – Kill on Sight (K-KoS) while preserving the `KoS-Kanonfode` folder, `KillOnSightDB` SavedVariables key and `KOSKANON` sync prefix.
- v0.4.8 skips hidden-tab rebuilding, builds the Stats list once when shown, runs Retail inspect polling only while work is queued or pending, and stops the sync send-queue ticker when idle.
- v0.4.7 adds manual class assignment for selected Player KoS entries, an Options version label and Escape closing for the main window.
- Official database initialization, player/guild rows and revision behavior remain unchanged; the Nearby range setting is additive. Class lookup runs in a separate read-only module and is covered by the included regression runner.
- The Lua regression and syntax runners are included in the separate evidence ZIP. No live in-game or two-client testing is claimed.
- The unused legacy command-help localization entry has been removed.
- The v0.4.0 feature set, protocol version 4, FULL/DELTA transfers, class hints, receiver read-only UI and removal of slash-command registrations are retained.
- Guild synchronization and taint behavior still require live testing across the target WoW Forever clients.
