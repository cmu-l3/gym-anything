# Task: Business Continuity Plan Training Deck

## Overview

**Occupation**: Emergency Management Directors / Business Continuity Planners
**Difficulty**: very_hard
**Domain**: Organizational Resilience / Business Continuity
**Standards**: ISO 22301:2019, FEMA Business Continuity Planning Guide

## Background

Business Continuity Planners create employee training presentations to ensure staff know their roles during organizational disruptions. A complete training deck covers BIA, recovery strategies, emergency response procedures (ideally as a visual flowchart), RTO/RPO targets, and exercise schedules. This task tests the ability to build a comprehensive, visually rich training presentation from a minimal draft.

## Starting State

- **Draft file**: `/home/ga/Documents/Presentations/bcp_training.odp` — 6-slide stub covering BCP basics, BIA, recovery strategies, a placeholder for the emergency response flowchart, and testing/exercises

## Goal / End State

The completed deck at `/home/ga/Documents/Presentations/bcp_training.odp` must:
1. Contain **at least 12 slides**
2. Include an **emergency response flowchart** — one slide with **at least 8 connected shapes** showing the incident response sequence
3. Include **at least 1 chart** (e.g., RTO/RPO comparison by recovery tier, or recovery timeline)
4. Have **speaker notes on at least 8 slides** with presenter talking points
5. Be **exported as PDF** to `/home/ga/Documents/Presentations/bcp_training.pdf`

## Success Criteria

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Slide count >= 12 | 25 | Required |
| One slide has >= 8 shapes (flowchart) | 30 | Required |
| At least 1 chart | 20 | Required |
| Speaker notes on >= 8 slides | 15 | Required |
| PDF export exists | 10 | Optional |
| **Pass threshold** | **65** | — |

## Verification Strategy

1. **ODP existence**: Fail immediately if missing
2. **Slide count**: Count `<draw:page>` elements
3. **Flowchart detection**: Count shape tags (`draw:custom-shape`, `draw:connector`, `draw:rect`, `draw:ellipse`, `draw:line`) per slide; require >= 8 on the best slide (excluding notes section)
4. **Charts**: Count `Object N/content.xml` entries containing `chart:chart`
5. **Notes**: Count `<presentation:notes>` elements with >25 non-tag chars
6. **PDF**: Copy and verify existence + size > 1KB

## Why This Is Hard

- Requires building 6 new slides with domain-specific BCP content
- Creating a flowchart in LibreOffice Draw tools requires placing, connecting, and labeling 8+ shapes
- Inserting a chart requires navigating the Insert menu and configuring chart data
- Adding notes to every slide requires switching to Notes view or the notes pane
- PDF export is a separate action (File > Export as PDF)
