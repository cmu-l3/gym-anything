# Task: market_brief_synthesis

**Environment**: wps_presentation_env
**Difficulty**: very_hard
**Occupation**: Market Research Analysts and Marketing Specialists
**Primary skill tested**: Cross-report contamination removal, slide reordering, client deliverable formatting

## Overview

A junior analyst at a market research consulting firm accidentally merged slides from two different research projects: a US Electric Vehicle Market brief and a Global Pharmaceutical Distribution report. The resulting 20-slide file at `/home/ga/Documents/EV_market_brief.pptx` needs to be fixed before delivery to Meridian Capital Partners, who commissioned only the EV brief.

Additionally, the EV slides themselves were assembled in the wrong order and need to be resequenced per the client's requested narrative structure.

A format specification document is at `/home/ga/Desktop/ev_brief_spec.txt`. The agent must read this document carefully — it describes both the contamination issue and the required slide order.

**Original file**: `/home/ga/Documents/EV_market_brief.pptx` (20 slides — do not modify)
**Output file**: `/home/ga/Documents/EV_brief_corrected.pptx` (should have 17 slides, first 10 in required order)

## What Makes This Very Hard

- The agent must read and interpret a structured specification document to understand both what to delete and how to reorder
- Pharmaceutical slides use realistic market research language — the agent must distinguish EV content from pharma distribution content
- The first 10 EV slides need to be in a specific client-mandated order that differs from their draft order; the agent must identify the right slides and move them
- Three contaminating slides are at non-contiguous positions (6, 13, 18) throughout the deck

## Contaminating Slides

Three pharmaceutical distribution slides must be removed:
1. "Global Pharma Distribution: Cold Chain Logistics Overview" (position 6)
2. "Pharmaceutical Wholesaler Concentration (HHI Analysis)" (position 13)
3. "Specialty Drug Distribution Margins by Channel" (position 18)

## Required Slide Order (after deletion)

1. Executive Summary
2. US EV Market Size and Growth
3. EV Adoption by Segment
4. Key OEM Market Share
5. Battery Technology Landscape
6. Charging Infrastructure Build-Out
7. Consumer Purchase Intent Drivers
8. Policy Environment: IRA and State Incentives
9. Competitive Threat: Chinese OEMs
10. 12-Month Outlook and Risks
_(remaining slides in their original relative order)_

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Output file EV_brief_corrected.pptx exists | 10 |
| Original EV_market_brief.pptx unchanged (20 slides) | 10 |
| Each pharma slide removed (×3) | 10 each = 30 |
| Each of first 10 slides in correct order (×10) | 5 each = 50 |
| **Total** | **100** |
| **Pass threshold** | **65** |

## Data Sources

- US EV sales 2023: 1.19 million units — IEA Global EV Outlook 2024
- US EV market share 2023: 7.6% — EIA, Apr 2024
- Average BEV transaction price Q1 2024: $53,633 — Kelley Blue Book, Apr 2024
- IRA Section 30D clean vehicle tax credit: Pub.L. 117-169 (Aug 16, 2022)
- Tesla US BEV market share ~55%: Cox Automotive Insights, Jan 2024
- Chevrolet Bolt EV base price $26,500: GM announcement, Jan 2024
- Public EV chargers: 169,015 — AFDC, January 2024
- BloombergNEF battery pack cost: LFP ~$126/kWh, NMC ~$139/kWh (Dec 2023)
- BYD global EV sales 2023: 3.02 million — BYD press release, Jan 2024
- Consumer EV consideration 38%: JD Power 2024 EV Consideration Study

## Verification Strategy

`export_result.sh` parses the output PPTX, scans all slides for pharmaceutical distribution keywords (pharma, drug, wholesaler, cold chain, 340B, biosimilar, GPO), and evaluates the order of the first 10 slides against the required sequence using fuzzy title matching.
