# Task: Connection Quality Diagnostics

## Overview

An IT manager must join a specific Jitsi meeting, navigate to multiple diagnostic/analytics features (connection stats, video quality settings, speaker stats, tile view), and compile a comprehensive diagnostic report. This task exercises features that are completely different from security/configuration tasks — requiring the agent to find technical monitoring tools hidden in the Jitsi UI.

**Difficulty**: Hard
**Occupation**: General and Operations Managers / IT Management (SOC 11-1021.00)
**Why Realistic**: Organizations running self-hosted Jitsi Meet need to document QoS (Quality of Service) metrics for SLA compliance. IT managers must navigate to the connection statistics panel, video quality settings, and speaker analytics to produce infrastructure performance reports.

---

## Goal

Join room `QualityTestRoom` and:
1. Open and read the connection statistics panel (network performance metrics)
2. Change video quality to highest available option
3. Switch to tile/grid view
4. Navigate to speaker statistics
5. Write diagnostic report to `/home/ga/Desktop/meeting_quality_report.txt`

---

## Success Criteria

1. Report exists and was created after task started
2. Report is substantial (>300 bytes)
3. Report contains meeting URL or room name
4. Report contains connection/network statistics vocabulary (RTT, packet loss, jitter, bitrate, latency, bandwidth)
5. Report contains video quality vocabulary (definition, HD, quality, resolution)
6. Report contains tile view or speaker stats vocabulary

---

## Scoring (100 points)

| Criterion | Points |
|-----------|--------|
| Report exists and modified after task start | 20 |
| Report contains room URL/name | 15 |
| Report contains connection stats vocabulary | 25 |
| Report contains video quality vocabulary | 20 |
| Report contains tile view or speaker stats vocabulary | 10 |
| Report > 300 bytes | 10 |
| **Pass threshold** | **60** |

---

## Verification Strategy

Procedure vocabulary used:
- `RTT`, `packet loss`, `jitter`, `bitrate`, `bandwidth`, `latency` — only appear in Jitsi's connection statistics panel
- `low definition`, `standard definition`, `high definition` — only appear in quality settings dialog
- `tile view`, `speaker stats`, `dominant speaker` — only appear after using those specific features

---

## Starting State

Firefox opens directly to `http://localhost:8080/QualityTestRoom` (pre-join screen). Agent joins, then navigates through multiple UI areas.

---

## Feature Coverage (distinct from all other tasks)

| Feature | Notes |
|---------|-------|
| Join specific room | QualityTestRoom |
| Connection statistics panel | Only in this task — RTT/jitter/packet loss |
| Video quality settings | Only in this task (coaching task mentions quality but not stats) |
| Tile/grid view toggle | Only in this task |
| Speaker statistics | Only in this task |

This is the only task requiring discovery and navigation of Jitsi's diagnostic/analytics features.
