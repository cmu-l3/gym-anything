# Task: esg_compliance_fix

**Environment**: wps_presentation_env
**Difficulty**: very_hard
**Occupation**: Sustainability Specialists
**Primary skill tested**: GRI Standards knowledge, regulatory compliance, slide editing, reordering

## Overview

The Head of Sustainability at Harrington Industrial Group must correct an ESG Disclosure Report presentation before it goes to the Board of Directors. An ESG auditor from Bureau Veritas has issued a review memo at `/home/ga/Desktop/esg_auditor_memo.txt` identifying three categories of errors in the 24-slide draft at `/home/ga/Documents/ESG_board_presentation.pptx`.

**Original file**: `/home/ga/Documents/ESG_board_presentation.pptx` (24 slides — do not modify)
**Output file**: `/home/ga/Documents/ESG_corrected.pptx` (should have 22 slides)

## What Makes This Very Hard

- The agent must read and interpret a regulatory memo written in GRI Standards and TCFD framework terminology
- Correcting GRI codes requires understanding which GRI number (302, 303, 305, 401) corresponds to which environmental/social topic (energy, water, emissions, employment)
- The TCFD reordering requires knowing the canonical TCFD framework sequence without being given current slide positions
- The contaminating marketing slides use realistic ESG language (ESG ratings, sustainability testimonials) that blends with the surrounding content
- Three distinct types of errors are present simultaneously — the agent must handle all three

## Injected Errors

### GRI Code Errors (slides 7, 10, 15)
| Slide | Wrong Title | Correct Title |
|-------|-------------|---------------|
| 7 | Emissions Disclosure (GRI 302-1) | Emissions Disclosure (GRI 305-1) |
| 10 | Energy Consumption Data (GRI 305-2) | Energy Consumption Data (GRI 302-1) |
| 15 | Water Withdrawal Data (GRI 401-3) | Water Withdrawal Data (GRI 303-3) |

### TCFD Pillar Order (slides 11-14)
| Draft position | Pillar | Correct position |
|---------------|--------|-----------------|
| 11 | Risk Management | 3rd |
| 12 | Governance | 1st |
| 13 | Metrics and Targets | 4th |
| 14 | Strategy | 2nd |

### Marketing Slides to Remove (slides 19, 23)
- "Harrington: A Great Place to Work — Employee Testimonials"
- "Harrington Industrial Group — Why Invest In Us"

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Output file ESG_corrected.pptx exists | 10 |
| Original ESG_board_presentation.pptx unchanged (24 slides) | 10 |
| Each GRI code corrected (×3) | 10 each = 30 |
| TCFD pillars in correct order | 20 |
| Each marketing slide removed (×2) | 10 each = 20 |
| Output slide count 21–23 | 10 |
| **Total** | **100** |
| **Pass threshold** | **65** |

## Data Sources

- GRI Standards 2021 (Universal Standards + Topical Standards):
  - GRI 302: Energy | GRI 303: Water and Effluents | GRI 305: Emissions | GRI 401: Employment
  - Published by the Global Reporting Initiative, globalreporting.org
- TCFD Recommendations (2021 update): governance → strategy → risk management → metrics & targets
  - Published by the Task Force on Climate-related Financial Disclosures, fsb-tcfd.org
- SBTi Corporate Net-Zero Standard: September 2021
- Bureau Veritas: real ESG assurance provider (bureauveri​tas.com)
- EPA eGRID: emission factors for Scope 2 (epa.gov/egrid)
- BLS TRIR benchmarks: Bureau of Labor Statistics Survey of Occupational Injuries and Illnesses 2023

## Verification Strategy

`export_result.sh` scans all slide titles for:
1. GRI codes — checks if wrong codes (302-1 in emissions slide, 305-2 in energy slide, 401-3 in water slide) still appear
2. TCFD pillar positions — records the slide position of each of the 4 TCFD slides and checks if they appear in Governance→Strategy→Risk Mgmt→Metrics order
3. Marketing keywords — flags any slide containing testimonial, "great place to work", "why invest", "forbes best employers", or dividend/revenue CAGR language
