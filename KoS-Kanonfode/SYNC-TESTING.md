# KoS-Kanonfode v0.4.3 — Guild Sync test

## Protocol compatibility
- This build uses sync protocol v4. Master and members must use a protocol-v4 build.
- A v4 master identifies a v3 member HELLO and reports a protocol mismatch; it does not send FULL/DELTA to that client.
- A v4 member that receives a v3 master packet reports a protocol mismatch. If a v3 master silently ignores the v4 HELLO, the member reports that no compatible protocol-v4 response was received and advises checking master version and addon-message permissions. No official data is applied across protocol versions.

## Digest semantics
- Digest covers only authoritative Player KoS and Guild KoS fields.
- Display-only `classHint` is deliberately excluded from the digest, but remains in FULL/DELTA records.
- A member's locally learned class, stats, sightings and Options must not change the digest.
- After an ACK digest mismatch, master retries FULL once. A second consecutive digest mismatch pauses sync to that peer for 5 minutes and displays the peer in master sync status. A successful ACK resets the mismatch counter.
- Digest is DJB2 for accidental corruption detection/integrity only; it is not authentication or a cryptographic signature.

## Setup
1. Back up the addon folder and the account SavedVariables file on both clients.
2. Install this exact protocol-v4 package on Calámir Dawnsinger and one guild member.
3. Both characters must be in the same guild, online in the open world and outside instances.
4. Confirm both clients are permitted by the realm to send addon messages.

## Expected automatic flow
1. The member detects Calámir Dawnsinger online in the guild roster.
2. The member sends HELLO through a private WHISPER addon message.
3. The master sends SAME, DELTA or FULL as required.
4. The member validates the sender, reassembles and checks the transfer, applies the official lists, preserves local stats/sightings/options, and acknowledges receipt.
5. Master changes to official Player/Guild lists are sent to checked-in peers.
6. No synchronization content appears in ordinary guild chat.

## Test cases
- New member receives FULL and reaches `Up to date`.
- Existing member with contiguous change history receives DELTA.
- Already-current member receives SAME.
- Add and remove one temporary Player KoS entry; verify both changes on the member.
- Add and remove one temporary Guild KoS entry; verify both changes on the member.
- Confirm member-local Seen/Wins/Losses and Options remain unchanged.
- Confirm known class hints display correctly after FULL and DELTA.
- Member has a locally learned class for a Player KoS entry while master class is unknown: digest still matches; no repeated FULL occurs; a single transfer completes.
- Force an official-data digest mismatch: exactly one FULL retry is allowed; the second consecutive mismatch enters a 5-minute backoff visible in master status.
- Confirm a successful ACK clears mismatch count and backoff.
- Confirm a v4 master identifies a v3 member HELLO, reports protocol mismatch, and sends no official data.
- Confirm a v4 member waiting on a v3 master reports no compatible protocol-v4 response; no official data is applied.
- Confirm two v4 clients synchronize normally.
- Take a member offline while the master changes a list, then log back in and verify automatic catch-up.
- Confirm no sync announcements are posted to guild chat.

## Operational note
The Options tab displays Guild Sync status. No manual slash command is provided or required. The current design requires the master to be online for initial sync; peer relay is not implemented.
