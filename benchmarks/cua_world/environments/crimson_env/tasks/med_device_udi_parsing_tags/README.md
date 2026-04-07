# Medical Device UDI Barcode Parser (`med_device_udi_parsing_tags@1`)

## Overview

**Environment**: `crimson_env` (Red Lion Crimson 3.0, Windows 11)
**Difficulty**: hard
**Occupation**: Packaging and Filling Machine Operators and Tenders
**Industry**: Medical Equipment and Supplies Manufacturing
**Standard**: FDA UDI Rule (21 CFR 801.20) / GS1 General Specifications
**Archetype**: Logic/String Manipulation

A medical device manufacturer is upgrading the end-of-line packaging HMI for a surgical stent cartoner. A USB barcode scanner acts as a keyboard wedge, feeding raw 32-character Unique Device Identifier (UDI) strings into the HMI. The agent, acting as the automation engineer, must configure the HMI to parse this raw string into distinct data fields using Crimson 3.0's built-in expression engine. The PLC only needs specific substrings (SKU, Batch, and Line Number) for routing logic.

## Rationale

**Why this task is valuable:**
- **New Skill Domain**: Tests the agent's ability to use Crimson's expression engine (`Mid`, `Right`, `TextToInt`) rather than just static tag configuration.
- **Data Type Mastery**: Evaluates handling of String tags vs Integer tags and the conversion between them.
- **Reading Comprehension & Math**: Requires the agent to calculate 0-based string indices and lengths from a fixed-width format specification.
- **Filtering Judgment**: The raw barcode contains 5 data fields, but the PLC integration spec explicitly states that only 3 are needed. The agent must filter out the unneeded data to save PLC memory.

**Real-world Context**: *Packaging and Filling Machine Operators* rely heavily on barcode serialization for Track & Trace compliance. SCADA systems frequently must ingest raw, concatenated scanner strings and slice them into individual PLC registers because legacy PLCs struggle with complex string manipulation.

## Task Description

**Goal:** Create a base String tag for the raw barcode, and 4 formula-driven tags that extract the SKU, Batch, and Line Number from the string based on the provided UDI format specification. Save the project as `med_device_udi.c3`.

**Starting State:** Red Lion Crimson 3.0 is open. The reference documents are located in `C:\Users\Docker\Desktop\CrimsonTasks\`.

**Expected Actions:**
1. Create a base String tag named `RawBarcode`.
2. Create `ParsedSKU` (String) with formula `Mid(RawBarcode, 5, 8)`.
3. Create `ParsedBatch` (String) with formula `Mid(RawBarcode, 14, 6)`.
4. Create `ParsedLineStr` (String) with formula `Right(RawBarcode, 2)` or `Mid(RawBarcode, 30, 2)`.
5. Create `ParsedLineInt` (Integer) with formula `TextToInt(ParsedLineStr, 10)`.
6. Save the project as `med_device_udi.c3` in `C:\Users\Docker\Documents\CrimsonProjects\`.

**Final State:** The project is saved and contains only the necessary tags with correct formulas. `PLANT` and `DATE` fields are intentionally omitted.

## Verification Strategy

### Primary Verification: CSV Export & Expression Parsing
The `export_result.ps1` post-task hook finds the saved `.c3` project, navigates to Data Tags, and triggers "Export Tags" to produce a CSV containing all configured tag properties, including formulas.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| S1 — Base Tag | 10 | `RawBarcode` tag created as a String data type. |
| S2 — SKU Parsing | 25 | `ParsedSKU` created with exact `Mid` formula matching index 5, length 8. |
| S3 — Batch Parsing | 25 | `ParsedBatch` created with exact `Mid` formula matching index 14, length 6. |
| S4 — Line Str Parsing | 20 | `ParsedLineStr` created with valid `Right` or `Mid` formula. |
| S5 — Line Int Casting | 20 | `ParsedLineInt` created as Integer with correct `TextToInt(..., 10)` cast. |
| **Total** | **100** | |

Pass Threshold: 70 points