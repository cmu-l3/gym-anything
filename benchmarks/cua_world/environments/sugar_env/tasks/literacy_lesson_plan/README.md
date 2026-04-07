# literacy_lesson_plan

## Task Overview

**Environment**: Sugar Learning Platform (OLPC)
**Difficulty**: Hard
**Occupation**: Elementary school teacher (2nd grade)
**Application**: Sugar Write (AbiWord)

## Domain Context

Elementary school teachers at OLPC-equipped schools use Sugar Write to create structured lesson plans for their classes. Weekly lesson plans typically include learning objectives, a daily schedule showing what students will do each day, and an assessment strategy. These plans are shared with curriculum coordinators and must follow a consistent format.

## Goal

Create a weekly literacy lesson plan document in Sugar Write with:
1. A **"Learning Objectives"** section heading with at least 2 objectives
2. A **"Daily Schedule"** section heading with a Mon–Fri table (at least 2 content rows)
3. An **"Assessment"** section heading with assessment description

Save the completed document to **two locations**:
- `/home/ga/Documents/literacy_plan.odt` (ODT file via File > Save As)
- Sugar Journal with title **"Literacy Plan Week 3"**

## Success Criteria

| Criterion | Points |
|-----------|--------|
| `literacy_plan.odt` saved and modified during task | 15 |
| File has content (>1000 bytes) | 5 |
| "Learning Objectives" section present | 20 |
| "Daily Schedule" section present | 20 |
| "Assessment" section present | 15 |
| Table element present in ODT XML | 10 |
| "Monday" found in table | 5 |
| Journal entry titled "Literacy Plan Week 3" | 10 |
| **Total** | **100** |

**Pass threshold**: score ≥ 70 AND all 3 headings present AND file exists

## Verification Strategy

1. `setup_task.sh` removes any pre-existing `literacy_plan.odt`, records timestamp, launches Write
2. `export_result.sh` parses the `.odt` ZIP archive → `content.xml` for section headings, table elements, and text content; also scans Sugar Journal (`~/.sugar/default/datastore/*/metadata/title`) for the expected title
3. `verifier.py` reads `/tmp/literacy_lesson_plan_result.json` and evaluates against all criteria

## ODT Verification Details

The `.odt` file is a ZIP archive containing `content.xml`. Verification uses Python's `zipfile` module to extract and parse the XML. Key XML patterns checked:
- `table:table` element for the schedule table
- Plain text (after stripping XML tags) searched for heading keywords

## Edge Cases

- AbiWord (Sugar Write) saves natively to Journal; the explicit File > Save As to `/home/ga/Documents/` is an additional required step
- If the agent saves only to Journal but not to the filesystem path, `file_exists=False` → task fails
- If the agent saves to a different filename or path, verification fails
- ODT files < 1000 bytes are likely incomplete (missing table/content)
