# Task: Board Meeting Security Lockdown

## Overview

An operations manager must join a specific Jitsi meeting room and apply multiple layers of security before the board meeting begins. This task requires discovering and using Jitsi's security features independently (Lobby and Room Lock/Password), sharing the invite, and writing a compliance-ready documentation summary.

**Difficulty**: Hard
**Occupation**: General and Operations Managers (SOC 11-1021.00)
**Why Realistic**: Executive board meetings are prime targets for "Zoombombing". Responsible meeting admins must enable lobby (for manual participant approval) AND a password (second factor), then distribute the credentials only through a secure channel — never in the meeting link itself.

---

## Goal

Join room `Q4ExecutiveBoard` and:
1. Enable Lobby mode (participants need approval)
2. Set meeting password to `Board2024!`
3. Copy the meeting invitation link to clipboard
4. Save security summary to `/home/ga/Desktop/board_security_summary.txt`

---

## Success Criteria

1. Summary file exists and was created after the task started
2. Summary is substantial (>200 bytes)
3. Summary contains the meeting room name or URL (Q4ExecutiveBoard)
4. Summary contains "lobby" (agent discovered and enabled it)
5. Summary contains "password" or "Board2024" (agent set the password)
6. Clipboard contains the Jitsi meeting URL

---

## Scoring (100 points)

| Criterion | Points |
|-----------|--------|
| Summary exists and modified after task start | 20 |
| Summary contains room name/URL | 20 |
| Summary contains "lobby" | 25 |
| Summary contains "password" or room lock vocabulary | 20 |
| Summary > 200 bytes | 15 |
| **Pass threshold** | **60** |

Note: Clipboard check is a secondary signal but not scored separately here (the lobby and password checks carry more weight as the core task).

---

## Verification Strategy

- `export_result.sh` checks the summary file and clipboard
- `verifier.py` reads result JSON via `copy_from_env`
- Gate: if no summary file, score=0

---

## Starting State

Firefox opens directly to `http://localhost:8080/Q4ExecutiveBoard` (the pre-join screen). The agent must join the meeting, then find and enable the security features.

---

## Feature Coverage

| Feature | Notes |
|---------|-------|
| Join a specific room | Navigate to Q4ExecutiveBoard |
| Security Options dialog | Lobby toggle + Room Lock/Password |
| Invite/share link | Copy to clipboard |
| File writing | Summary to Desktop |

No existing task covers: specific-room-join + lobby + password + invite + file documentation together.
