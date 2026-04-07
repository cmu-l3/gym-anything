# temperature_science_report

## Task Overview

**Environment**: Sugar Learning Platform (OLPC)
**Difficulty**: Hard
**Occupation**: 5th-grade science teacher
**Application**: Sugar Write (AbiWord)

## Domain Context

5th-grade science teachers at OLPC schools use Sugar Write to create student lab report templates. After conducting experiments, teachers compile class results into structured reports with data tables, analysis sections, and conclusions. The temperature measurement experiment (recording daily outdoor temperatures over 5 days) is a standard elementary meteorology exercise.

## Goal

Create a science lab report in Sugar Write containing:

1. A **data table** with 2 columns (Day, Temperature °C) and 5 data rows:
   | Day | Temperature (°C) |
   |-----|-----------------|
   | Day 1 | 22 |
   | Day 2 | 24 |
   | Day 3 | 21 |
   | Day 4 | 26 |
   | Day 5 | 23 |

2. An **"Analysis"** section (exact heading) discussing temperature patterns

3. A **"Conclusion"** section (exact heading) summarizing experiment findings

Save the document to `/home/ga/Documents/temperature_report.odt`.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| `temperature_report.odt` saved and modified during task | 15 |
| File has content (>1000 bytes) | 5 |
| Data table present in ODT XML | 15 |
| Temperature 22°C present | 5 |
| Temperature 24°C present | 5 |
| Temperature 26°C present | 5 |
| All 5 temperatures (22,24,21,26,23) present | 10 (bonus for complete set) |
| "Analysis" section heading present | 20 |
| "Conclusion" section heading present | 20 |
| **Total** | **100** |

**Pass threshold**: score ≥ 65 AND has_analysis=True AND has_conclusion=True AND has_table=True AND file_exists=True

## Verification Strategy

1. `setup_task.sh` removes any pre-existing `temperature_report.odt`, records timestamp, launches Write
2. `export_result.sh` parses the `.odt` ZIP → `content.xml`, strips XML tags, searches for section keywords and temperature values (22, 24, 21, 26, 23), checks for `table:table` element
3. `verifier.py` reads `/tmp/temperature_science_report_result.json` and evaluates against all criteria

## Temperature Data Ground Truth

The exact temperature values that must appear in the document:
- Day 1: **22°C** (coldest day 3 has 21°C, day 5 has 23°C)
- Day 2: **24°C**
- Day 3: **21°C** (coldest)
- Day 4: **26°C** (hottest)
- Day 5: **23°C**

All values come from the task description directly, following the "hard" task pattern (expected values stated, no UI path given).

## Edge Cases

- Temperature values may appear with or without the "°C" suffix; verification uses bare numbers (e.g., `\b22\b`)
- The verifier does NOT distinguish between the number 22 appearing in the temperature table vs. appearing elsewhere (e.g., "22 students") — this is acceptable for the hard difficulty level
- If the agent omits the table and just types the temperatures inline, `has_table=False` → task fails even if temperatures are present
- AbiWord's "Save As" dialog may default to DOC format; agent must ensure ODT format is selected
