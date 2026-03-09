# Task: Emergency Response Meeting Coordination

## Overview

An IT operations manager must rapidly deploy and fully configure a secure emergency incident response meeting in Jitsi Meet. This is the highest-difficulty task, requiring the agent to use the most feature combinations: room creation, lobby, password, mute policy, in-meeting chat, invite link copying, and professional incident documentation — all in a time-sensitive scenario.

**Difficulty**: Very Hard
**Occupation**: General and Operations Managers (SOC 11-1021.00) / IT Incident Response
**Why Realistic**: Incident response coordinators need secure, fast meeting deployment with verified attendance confirmation via chat, controlled access (lobby), and immutable documentation (report file). This is a standard NIST IR protocol step.

---

## Goal

Set up meeting room `Incident-Response-CRIT001` with:
1. Lobby enabled (responders need approval)
2. Meeting password set
3. Everyone-starts-muted policy enabled
4. Chat message sent: `INCIDENT RESPONSE ACTIVE - All responders acknowledge attendance`
5. Invite link copied to clipboard
6. Full incident report at `/home/ga/Desktop/incident_response_meeting_report.txt`

---

## Success Criteria

1. Report file exists and was created after task started
2. Report is substantial (>400 bytes — incident reports must be comprehensive)
3. Report contains the meeting URL with the correct room name
4. Report documents lobby feature
5. Report documents password/lock feature
6. Clipboard contains meeting URL (invite link was copied)
7. Report contains the chat message text or references sending chat

---

## Scoring (100 points)

| Criterion | Points |
|-----------|--------|
| Report exists and modified after task start | 15 |
| Report contains correct room URL/name | 15 |
| Report contains "lobby" | 20 |
| Report contains "password" or room lock | 15 |
| Report references chat message or "INCIDENT RESPONSE" | 15 |
| Clipboard contains meeting URL | 10 |
| Report > 400 bytes | 10 |
| **Pass threshold** | **65** |

---

## Verification Strategy

- `export_result.sh` checks report file, clipboard, and prosody room existence
- Procedure vocabulary: "lobby" (Security Options), "password" (Room Lock), chat message text
- Gate: if no report exists, score=0

---

## Starting State

Firefox opens to `http://localhost:8080` (home page). Agent creates the room and configures everything from scratch.

---

## Feature Coverage Matrix (all 5 new tasks)

| Feature | Task 1 RSI | Task 2 Board | Task 3 Coaching | Task 4 Quality | Task 5 Emergency |
|---------|-----------|-------------|----------------|----------------|-----------------|
| Room creation | ✓ | | ✓ | | ✓ |
| Display name | ✓ | | ✓ | | |
| Lobby | ✓ | ✓ | | | ✓ |
| Password | ✓ | ✓ | | | ✓ |
| Invite copy | ✓ | ✓ | | | ✓ |
| Chat | | | | | ✓ |
| Virtual background | | | ✓ | | |
| Video quality | | | ✓ | ✓ | |
| Connection stats | | | | ✓ | |
| Tile view | | | | ✓ | |
| Speaker stats | | | | ✓ | |
| Mute policy | ✓ | | ✓ | | ✓ |
| File report | ✓ | ✓ | ✓ | ✓ | ✓ |

No single feature appears in all 5 tasks. Each task exercises a distinct combination.
