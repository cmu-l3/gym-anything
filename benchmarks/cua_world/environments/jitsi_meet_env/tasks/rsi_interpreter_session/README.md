# Task: RSI Interpreter Session Setup

## Overview

A professional interpreter must configure a complete Remote Simultaneous Interpreting (RSI) conference session in Jitsi Meet. This task tests multi-feature meeting configuration including security controls, display identity, audio policy management, invite sharing, and professional documentation.

**Difficulty**: Very Hard
**Occupation**: Interpreters and Translators (SOC 27-3091.00)
**Why Realistic**: Interpreters who conduct RSI sessions via Jitsi Meet must configure the meeting *before* participants join — enabling lobby so they can be seated first, locking the room to prevent unauthorized access, enforcing mute policies so participants don't interfere with interpretation audio, and sharing the invite link with event organizers.

---

## Goal

Set up a secure, professionally-configured Jitsi meeting room named `RSI-IntlConf-2024` with:
1. Lobby/waiting-room feature enabled (participants must be approved)
2. Meeting password/room lock enabled
3. Display name set to `Lead Interpreter EN/FR`
4. All-participants-start-muted policy enabled
5. Meeting invitation link copied to clipboard
6. Comprehensive setup report written to `/home/ga/Desktop/rsi_conference_report.txt`

---

## Success Criteria

1. **Report file exists** and was created/modified after the task started
2. **Report is substantial** (>300 bytes)
3. **Report contains the meeting URL** (localhost:8080/RSI-IntlConf-2024 or similar)
4. **Report documents the lobby feature** (the word "lobby" appears)
5. **Report documents the mute policy** ("muted" or "microphone" in report)
6. **Clipboard contains the meeting URL** (copied invite link)

---

## Scoring (100 points)

| Criterion | Points |
|-----------|--------|
| Report exists and modified after task start | 20 |
| Report size > 300 bytes | 10 |
| Report contains meeting URL | 15 |
| Report contains "lobby" | 20 |
| Report contains "muted"/"microphone" | 15 |
| Clipboard contains meeting URL | 20 |
| **Pass threshold** | **60** |

---

## Verification Strategy

- `export_result.sh` runs inside the VM, checks the report file, reads clipboard with `xclip`
- `verifier.py` reads `/tmp/rsi_interpreter_session_result.json` via `copy_from_env`
- Gate: if no report exists, score=0 immediately

---

## Starting State

Firefox is open to `http://localhost:8080` (the Jitsi home page). No meeting is active.

---

## Key Jitsi Features Required

1. **Meeting room creation** — enter room name and join
2. **Security Options** — contains Lobby toggle and Room Lock/Password
3. **Settings → Participants** — contains "Everyone starts muted" toggle
4. **Display name** — set before or during meeting via profile/settings
5. **Invite feature** — copy meeting link to clipboard

---

## Notes for Task Creator

- All existing verifiers in this environment are stubs. This task has a real programmatic verifier.
- Jitsi stable-9753 with `ENABLE_LOBBY=1` supports both Lobby and Password/Room-lock.
- The report file approach (Lesson 27) is used because Jitsi has no queryable database.
- Procedure vocabulary checked: "lobby" (only appears after navigating Security Options and enabling it).
