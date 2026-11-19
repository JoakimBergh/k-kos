# KoS-Kanonfode — BG/Arena protection

The BG/Arena activity gate was introduced before v0.1.1 and has been confirmed in-game by the user on the v0.1.x baseline: KoS correctly pauses in Battlegrounds and resumes outside them. v0.2.0 does not intentionally alter this protection.

## Behavior
- `Core:IsKoSActive()` is the central gate for Battleground/Arena and PvE-instance suppression.
- Detection, Nearby, notifications and statistics are gated while KoS is inactive.
- Battleground/Arena entry clears Nearby without resolving encounters or incrementing Seen.
- Stats ignores outcome events while disabled and discards active encounters on disable without resolving them.
- Notifier entry points and low-level chat/sound/flash calls are gated. Pending stealth warning timers and warning frames are cancelled/hidden on disable.

## v0.2.0 validation status
- The BG/Arena behavior itself was confirmed by the user on the earlier working baseline.
- v0.2.0 changes are limited to Honor/Profile removal, single-settings migration, and Nearby membership markers, apart from version/documentation metadata.
- v0.2.0 still requires an in-client regression test to confirm the cleanup did not affect normal use or the BG/Arena gate.
