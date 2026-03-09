# Task: correct_paper_year

## Overview

A researcher imported a batch of classic academic papers into Zotero, but two papers received incorrect publication years due to a data entry error. The agent must identify both papers and correct their years using Zotero's Info panel. This tests the ability to locate specific items by title/author, edit metadata fields, and save changes.

## Target Papers

| Paper | Author | Wrong Year | Correct Year |
|-------|--------|-----------|-------------|
| On the Electrodynamics of Moving Bodies | Albert Einstein | **1906** | **1905** |
| A Mathematical Theory of Communication | Claude E. Shannon | **1950** | **1948** |

**Historical context:**
- Einstein published his special relativity paper in *Annalen der Physik* in **1905** — not 1906
- Shannon published his landmark information theory paper in *Bell System Technical Journal* in **1948** — not 1950

## Task Description

1. Open Zotero (running, 10 classic papers pre-loaded with the two errors)
2. Click on **"On the Electrodynamics of Moving Bodies"** to select it
3. In the right panel, click the **Info** tab
4. Find the **Date** field — it currently shows **1906**
5. Click on the date field and edit it to **1905**
6. Press **Enter** or click elsewhere to save
7. Now click on **"A Mathematical Theory of Communication"**
8. In the right panel, find the **Date** field — it currently shows **1950**
9. Edit it to **1948**
10. Press **Enter** or click elsewhere to save

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| Einstein paper year corrected to 1905 | 50 | Must contain "1905" in the date field |
| Shannon paper year corrected to 1948 | 50 | Must contain "1948" in the date field |
| **Total** | **100** | **Pass threshold: 80** |

Both corrections are required for a passing score. Fixing only one paper scores 50 pts (fail).

## Verification Strategy

- `export_result.sh` queries `itemData` (fieldID=6 is the date field) for both papers by exact title
- Checks whether the stored date value contains the correct year string
- `verifier.py` reads `/tmp/correct_paper_year_result.json`

## Database Schema Reference

```sql
-- Query current year for a specific paper
SELECT v.value AS current_date
FROM items i
JOIN itemData d ON i.itemID = d.itemID AND d.fieldID = 1  -- title
JOIN itemDataValues v_title ON d.valueID = v_title.valueID AND v_title.value LIKE '%Electrodynamics%'
JOIN itemData d2 ON i.itemID = d2.itemID AND d2.fieldID = 6  -- date
JOIN itemDataValues v ON d2.valueID = v.valueID;

-- Field ID reference:
-- fieldID=1  → title
-- fieldID=6  → date
-- fieldID=38 → publicationTitle
```

## Setup State

- 10 classic papers seeded via `seed_library.py --mode classic_with_errors`
- Einstein's date field is deliberately set to **1906** (correct: 1905)
- Shannon's date field is deliberately set to **1950** (correct: 1948)
- Setup script verifies both corruptions exist before the task starts
- Zotero running and displaying the 10 papers

## Edge Cases

- Agent fixes Einstein but not Shannon (or vice versa) → 50 pts, not passing
- Agent changes year to something else (e.g., "1907") → 0 pts for that paper, specific feedback given
- Agent deletes the date field entirely → year will be empty → 0 pts for that paper
- Zotero stores the date as a full date string (e.g., "1905-01-01") → verification checks if correct year is contained anywhere in the value string (substring match)
