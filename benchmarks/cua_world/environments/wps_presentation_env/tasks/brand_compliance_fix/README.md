# Task: brand_compliance_fix

## Overview
**Difficulty**: very_hard
**Occupation**: Advertising Sales Agent
**Industry**: Cloud Infrastructure / MarTech

An advertising sales agent must transform a technical Apache performance deck into a brand-compliant CloudServer Pro client pitch deck by reading and implementing a brand guidelines spec file.

## What the Agent Must Do
1. Read `/home/ga/Desktop/brand_guidelines.txt`
2. Fix slide 1 title to "CloudServer Pro: Performance Benchmarking Solutions"
3. Replace last slide with a "Contact Us" slide containing:
   - Title: "Contact Us"
   - Email: sales@cloudserverpro.com
   - Phone: 1-800-CLOUD-PRO
4. Fix all ALL CAPS slide titles (4 injected: slides 5, 9, 14, 20)
5. Save to NEW file `/home/ga/Documents/branded_cloudserver.pptx`

## Brand Violations Injected
- Slide 1: title changed to wrong lowercase text
- Slides 5, 9, 14, 20 (1-indexed): titles changed to ALL CAPS

## Scoring (100 pts)
- 15 pts: branded file exists
- 25 pts: exact first slide title match
- 15 pts: last slide title = "Contact Us"
- 15 pts: email in last slide body
- 5 pts: phone in last slide body
- 5 pts × 4 = 20 pts: ALL CAPS fixes
- **Pass threshold**: 65 pts

## Why This Is Hard
- Agent must read and interpret a specification file
- Must make precise text edits to slide titles
- Must create a new closing slide with specific content
- Must use Save As to a different filename
- Requires scanning all slides for ALL CAPS violations
- Exact string matching for title and contact info

## Files
- `task.json` — task specification
- `setup_task.sh` — injects brand violations, writes guidelines, launches WPS
- `export_result.sh` — extracts branded file slide data to JSON
- `verifier.py` — multi-criterion brand compliance verification
