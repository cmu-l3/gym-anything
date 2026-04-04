# Task: Virtual Coaching Session Setup

## Overview

A fitness instructor must configure a complete virtual coaching environment in Jitsi Meet, using multiple unrelated features: virtual background, display name, video quality settings, mute policy, and professional documentation. The task tests discovery of Jitsi's media configuration features which are spread across different dialogs.

**Difficulty**: Very Hard
**Occupation**: Exercise Trainers and Group Fitness Instructors (SOC 39-9031.00)
**Why Realistic**: Remote fitness coaching is a major industry segment. Instructors need: a professional background (virtual bg), clear video (quality settings), controlled audio environment (participants start muted), proper identification (display name), and replicable documentation for studio admins.

---

## Goal

Set up the `FitCoach-LiveSession` room with:
1. Virtual background enabled (blur or image)
2. Display name set to `Coach Rivera`
3. Everyone-starts-muted policy enabled
4. Video quality set to highest available
5. Configuration guide written to `/home/ga/Desktop/coaching_session_config.txt`

---

## Success Criteria

1. Config guide exists and was created after the task started
2. Guide is substantial (>300 bytes)
3. Guide contains the meeting URL
4. Guide documents virtual background (words: "virtual", "background", "blur")
5. Guide documents mute policy ("muted", "microphone", "participants start")
6. Guide contains coaching-relevant content ("coach", "fitness", "session", "instructor")

---

## Scoring (100 points)

| Criterion | Points |
|-----------|--------|
| Guide exists and modified after task start | 20 |
| Guide contains meeting URL | 15 |
| Guide contains virtual background vocabulary | 25 |
| Guide contains mute policy vocabulary | 20 |
| Guide contains coaching/fitness vocabulary | 10 |
| Guide > 300 bytes | 10 |
| **Pass threshold** | **60** |

---

## Verification Strategy

- `export_result.sh` checks the guide file content for procedure vocabulary
- Key: "virtual background" terminology only appears after navigating Jitsi's background selection dialog
- Key: "everyone starts muted" or "start muted" only appears after navigating meeting settings

---

## Starting State

Firefox opens to `http://localhost:8080` (Jitsi home page). Agent must create the room, configure all settings, then write documentation.

---

## Feature Coverage (distinct from other tasks)

| Feature | Notes |
|---------|-------|
| Room creation | New room FitCoach-LiveSession |
| Virtual background | Background blur/image — unique to this task |
| Display name setting | Set to Coach Rivera |
| Video quality settings | Highest quality — unique to this task |
| Everyone-starts-muted | Audio policy |
| Documentation | Config guide |

This is the only task that requires virtual background configuration — a feature not tested in any existing or new task.
