# Task: investor_pitch_audit

**Environment**: wps_presentation_env
**Difficulty**: very_hard
**Occupation**: Financial Manager
**Primary skill tested**: Error discovery, document compliance, slide editing

## Overview

You are the Financial Controller at Meridian Technology Group. The IR team has prepared a 30-slide investor presentation for the Q3 2024 earnings call, but the Legal & Compliance team has flagged the draft as non-compliant. A compliance checklist has been left at `/home/ga/Desktop/meridian_compliance.txt`. Read it carefully — it describes the issues in general terms without pointing to specific slide numbers.

The original presentation is at `/home/ga/Documents/financial_report.pptx`. **Do not modify this file.** Save the corrected presentation as `/home/ga/Documents/Q3_board_corrected.pptx`.

## Compliance Issues to Fix

The compliance document (which the agent must read and interpret) describes:

1. **Quarter reference errors**: Some slides have "Q2 2024" in the title instead of "Q3 2024" (the correct reporting period). The agent must find all instances and correct them.

2. **Competitor information**: At least one slide contains financial data from a competitor company (not Meridian). This constitutes a potential Regulation FD violation. The slide must be identified and deleted.

3. **Missing Forward-Looking Statements disclaimer**: SEC guidance requires that any earnings presentation with forward-looking statements include a "Forward-Looking Statements" disclaimer slide as slide 2 (immediately after the title slide). The compliance document provides the exact text that must appear in the body.

## What Makes This Very Hard

- The compliance document describes issues in general terms without naming slide numbers. The agent must read and interpret a written compliance document, then scan the presentation to find the actual violations.
- The FLS disclaimer text is provided in the compliance document and must be copied accurately.
- The competitor slide content looks like real financial data — the agent must identify it as belonging to a different company.
- Four different slides have the quarter error, spread across a 30-slide deck.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Output file Q3_board_corrected.pptx exists | 10 |
| Original financial_report.pptx unchanged (30 slides) | 10 |
| Each "Q2 2024" title corrected to "Q3 2024" (×4) | 5 each = 20 |
| Competitor slide removed | 20 |
| Forward-Looking Statements slide present | 20 |
| FLS at slide 2 + correct body text | 20 |
| **Total** | **100** |
| **Pass threshold** | **65** |

## Data Sources

- US GDP Q3 2024: 2.8% annualized — BEA Advance GDP Estimate, Oct 30, 2024 (BEA-2024-49)
- US GDP Q2 2024: 3.0% annualized — BEA Second Estimate, Aug 29, 2024
- US Unemployment Sep 2024: 4.1% — BLS Employment Situation Summary, Oct 4, 2024
- Federal Funds Rate: 4.75%–5.00% — FOMC Statement, Sep 18, 2024
- Consumer Spending Q3 2024: +3.7% — BEA, Oct 30, 2024
- Forward-Looking Statements language follows standard SEC Regulation S-K boilerplate

## Verification Strategy

`export_result.sh` parses `/home/ga/Documents/Q3_board_corrected.pptx` using `python-pptx` and extracts:
- All slide titles and body text previews
- Positions of any remaining "Q2 2024" references
- Positions of any slides mentioning "Apex Digital Solutions" or "APXD"
- Position and body text of any slide titled "Forward-Looking Statements"
- Slide count of the original file (to verify it was not modified)

`verifier.py` scores each criterion independently. An agent that fixes the quarter errors and removes the competitor slide but misses the disclaimer can still pass.
