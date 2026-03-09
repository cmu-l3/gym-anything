# Home Compost Troubleshooting Tracker Task (`compost_diagnosis@1`)

## Overview

This task tests an agent's ability to create a diagnostic spreadsheet for troubleshooting a malfunctioning home composting system. The agent must organize messy handwritten notes into structured data, categorize materials by chemical properties, calculate carbon-to-nitrogen ratios using formulas, and identify periods of imbalance that caused decomposition problems.

## Task Description

A household started backyard composting three months ago but encountered problems: bad smell (ammonia odor), fruit flies, and soggy, slow-decomposing material. They kept rough handwritten notes on scrap paper and need to create a proper tracking spreadsheet to diagnose what went wrong.

## Skills Tested

- **Data Organization**: Converting unstructured notes into structured format
- **Scientific Categorization**: Understanding green (nitrogen-rich) vs brown (carbon-rich) materials
- **Formula Creation**: Creating calculations for ratio analysis
- **Problem Diagnosis**: Identifying patterns and root causes
- **Spreadsheet Formatting**: Creating readable, usable documents

## Setup

The task creates a spreadsheet (`compost_notes.xlsx`) with rough, unstructured notes containing:
- Dates of material additions (June-July)
- Material descriptions (kitchen scraps, grass clippings, leaves, cardboard, etc.)
- Volume estimates (often vague: "big bag", "about 3 cups")
- Problem observations (smell on June 15, fruit flies, soggy material)
- User's uncertainty about what went wrong

## Expected Solution

The agent should:

1. **Create structured columns**: Date, Material, Category (Green/Brown), Volume, Notes
2. **Extract and organize data** from the rough notes into the structured format
3. **Categorize materials correctly**:
   - **GREEN (nitrogen-rich)**: kitchen scraps, coffee grounds, grass clippings, weeds, fruit waste, vegetable peels
   - **BROWN (carbon-rich)**: dry leaves, paper, cardboard, wood chips
4. **Create formulas** to calculate green-to-brown ratio (e.g., `=COUNTIF()`, `=SUM()`)
5. **Identify the problem**: Too many greens added early on (especially grass clippings and kitchen waste in June)
6. **Add diagnosis section**: Note that excess greens caused the ammonia smell and recommend adding more browns

## Verification Criteria

The verifier checks:

- **File Structure (20%)**: Proper headers (Date, Material, Category, etc.)
- **Data Completeness (20%)**: At least 12-15 entries extracted and organized from rough notes
- **Categorization Accuracy (25%)**: Correct classification of materials as green/brown (at least 80% accuracy)
- **Formula Presence (15%)**: Calculation of ratios or counts using spreadsheet formulas
- **Problem Diagnosis (10%)**: Identification of green/brown imbalance issue
- **File Readability (10%)**: Overall usability and formatting

**Pass threshold**: 70%

## Difficulty

**Medium** - This task requires:
- Data extraction from unstructured text
- Domain knowledge (composting science)
- Formula creation
- Diagnostic reasoning
- Organizational skills

It's more complex than basic formatting but doesn't require advanced spreadsheet features.

## Real-World Context

This task simulates authentic problem-solving:
- Converting informal records into analytical tools
- Applying scientific principles to troubleshoot issues
- Creating diagnostic systems from incomplete data
- Making actionable recommendations based on pattern analysis

This mirrors real scenarios in environmental management, gardening, agriculture, and any field requiring retrospective problem diagnosis.

## Files

- `task.json`: Task configuration (35 steps, 240s timeout)
- `setup_task.sh`: Creates rough notes spreadsheet and launches ONLYOFFICE
- `export_result.sh`: Saves and closes spreadsheet
- `verifier.py`: Verifies structured data, categorization, formulas, and diagnosis
- `README.md`: This documentation file

## Educational Value

This task teaches:
- Converting messy real-world data into structured analysis tools
- Applying domain knowledge during data organization
- Using formulas for diagnostic calculations
- Correlating temporal patterns with problem manifestation
- Creating actionable recommendations from data analysis