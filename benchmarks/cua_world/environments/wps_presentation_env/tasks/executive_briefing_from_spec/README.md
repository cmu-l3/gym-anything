# Task: executive_briefing_from_spec

## Overview
**Difficulty**: very_hard
**Occupation**: General/Operations Manager
**Industry**: Technology Infrastructure

An operations manager must condense a 48-slide technical performance presentation into a concise executive briefing for the board of directors, following a detailed specification file.

## What the Agent Must Do
1. Read `/home/ga/Documents/executive_briefing_spec.txt` to get requirements
2. Open and review the 48-slide `performance.pptx`
3. Create a new file `/home/ga/Documents/executive_briefing.pptx` with:
   - Exactly 12 or fewer slides (condensed from 48)
   - First slide title: "Apache Infrastructure: Q4 2024 Executive Briefing"
   - Last slide containing "Q&A" or "Questions"
   - A professional non-default theme applied
4. Leave the original `performance.pptx` unchanged

## Scoring (100 pts)
- 15 pts: briefing file exists
- 20 pts: ≤12 slides
- 25 pts: exact first slide title match
- 15 pts: last slide has Q&A/Questions
- 15 pts: non-default theme applied
- 10 pts: fewer slides than original (truly condensed)
- **Pass threshold**: 65 pts

## Why This Is Hard
- Agent must read and interpret a spec file
- Must make creative decisions about which slides to keep
- Exact title string match required
- Must use WPS File > Save As to create a new file (different from original)
- Non-default theme requires navigating WPS Design panel
- 100-step budget needed for the full workflow

## Files
- `task.json` — task specification
- `setup_task.sh` — writes spec file, resets presentation, launches WPS
- `export_result.sh` — extracts briefing metadata to JSON
- `verifier.py` — checks all spec requirements
