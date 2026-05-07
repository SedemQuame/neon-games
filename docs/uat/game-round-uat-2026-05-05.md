# Glory Grid Game Round UAT

Date: 2026-05-05
Environment: local web build at `http://127.0.0.1:8087`
Backend URL: `https://neon-games-production.up.railway.app`

## Acceptance Criteria

- Every solo and multiplayer game must open to a non-empty screen.
- Demo mode must run without changing wallet balance.
- Real mode must either start a funded round or show a clear reason why it cannot start.
- Round transaction acknowledgement should be visible within 1 second for real-money actions.
- Long-running artifacts, such as dice rolls, coin flips, and flights, must show an intentional countdown or live progress state.
- Players must see the round result, winner/loser state, choices, and payout.
- Fixed bottom controls must not hide the primary play button, result, or status text.

## Browser UAT Results

| Area | Result | Notes |
| --- | --- | --- |
| Landing to guest lobby | Pass | App loaded and guest login reached the lobby. Cold web startup still shows a loading panel for several seconds. |
| Desktop lobby layout | Pass | Lobby content is inside the centered desktop container. |
| Live player count | Pass with fallback | Shows real connected user count locally (`1 Live`). The app now suppresses the production backend compatibility error until the updated game service is deployed. |
| Solo: Neon Rise demo round | Pass | Demo resolved visibly and wallet stayed unchanged. No empty screen observed. |
| Multiplayer demo: Rock Paper Scissors | Pass | Computer choice visibly shuffles/resolves, result explains both choices and payout. |
| Multiplayer demo: Dice Duel | Needs UI fix | Dice artifact rolls with 10-second countdown and lands correctly, but bottom fixed controls partially cover the play/result area on desktop-height web view. |
| Multiplayer demo: Coin Toss Clash | Pass | Coin artifact flips with 10-second countdown and settles with clear win/loss and payout text. |
| Multiplayer real room browser | Partial pass | Room list and join flow render. Full real-money multiplayer round was blocked by single-browser testing and `$0.00` wallet. |
| Real transaction under 1 second | Not fully verified | A true pass requires two funded unique accounts in the same room. Current code still uses an 8-second socket acknowledgement timeout, so production latency should be measured separately before release. |

## Issues Found

### UAT-001: Live stats request leaked `unknown message type`

Severity: Medium

The frontend was sending `GET_LIVE_STATS`, but the currently deployed production game service does not yet support that socket message. The error appeared inside multiplayer UI as `unknown message type`.

Status: Fixed in client. The client now treats that specific live-stats compatibility response as unsupported and falls back to the current connected user count instead of showing an error.

### UAT-002: Room recovery status stayed visible after room state returned

Severity: Medium

After joining/recovering a room, the UI could keep showing `Room connection lost. Reconnecting...` even after a valid `ROOM_STATE` arrived.

Status: Fixed. Room adoption now clears stale room-connection-lost statuses.

### UAT-003: Dice Duel fixed bottom controls overlap the round controls

Severity: High

On the tested desktop-height viewport, the fixed Demo/Real bar partially covers the Dice Duel play button and result/status area. The game is still playable, but the primary action and outcome text are visually crowded.

Status: Open.

### UAT-004: Dice Duel result lacks explicit user win/loss detail in the visible panel

Severity: Medium

Dice Duel shows the landed roll and a generic settled message. Compared with Rock Paper Scissors and Coin Toss, the visible result panel does not clearly say whether the player won or lost and why.

Status: Open.

### UAT-005: Multiplayer real round cannot be fully accepted from one browser session

Severity: UAT blocker

A full real multiplayer round requires at least two ready players with distinct accounts and sufficient wallet balance. The tested session had `$0.00`, so the final real-money start/settlement path and under-1-second acknowledgement SLA remain unverified.

Status: Blocked pending funded two-account UAT.

## UAT Checklist For Next Pass

Run the following with two funded accounts, preferably one host and one joiner:

1. Create a public room for each multiplayer game.
2. Join the room from a second account using code and shared link.
3. Set ready on both accounts.
4. Start the round and measure time from click to visible lock/round acknowledgement.
5. Submit moves from both accounts where required.
6. Confirm countdown/progress animation appears for Dice Duel and Coin Toss Clash.
7. Confirm result screen shows every player choice, winner, loser, and payout.
8. Confirm wallet balance updates only in real mode.
9. Confirm leaving/restarting the room resets the round without stale status messages.

## Commands Run

- `flutter analyze`
- `go test ./...` in `apis/game-session-service`
- `flutter build web --dart-define=GAMEHUB_BASE_URL=https://neon-games-production.up.railway.app`

