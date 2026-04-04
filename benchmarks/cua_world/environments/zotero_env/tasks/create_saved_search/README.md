# Task: create_saved_search

## Overview

A researcher with a growing Zotero library wants to set up a persistent, dynamic filter that automatically shows recent publications. Zotero's "Saved Search" feature allows defining search conditions that update automatically as the library grows. This task tests the ability to create a named saved search with a date-based filter condition.

## Target

- **Search name**: `Papers Since 2010` (exact, case-sensitive)
- **Condition**: Date/Year is after or equal to 2010
- **Expected matching papers**: ~8 papers (AlexNet 2012, GANs 2014, Deep Learning 2015, ResNet 2016, AlphaGo 2016, Transformer 2017, BERT 2019, GPT-3 2020)

## Task Description

1. Open Zotero (running, 18 papers pre-loaded spanning 1905–2020)
2. Go to **Edit** menu → **New Saved Search...** (or right-click "My Library")
3. In the dialog:
   a. Set the search name to exactly: **`Papers Since 2010`**
   b. Set condition: **Date** (or Year) **is after** → value **`2009`**
      (or use "is in the year" / ">=" with value "2010")
4. Click **Save**
5. The saved search appears in the left panel and shows ~8 matching papers

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| Saved search named exactly "Papers Since 2010" exists | 40 | Exact name match; 25 pts for close match |
| Search has at least one condition configured | 20 | Cannot be empty condition |
| Condition involves the date or year field | 20 | `date`, `year`, `pubdate`, `dateModified` accepted |
| Year threshold is 2009–2015 (to capture 2010+ papers) | 20 | Flexible: accepts "2009" or "2010" as threshold |
| **Total** | **100** | **Pass threshold: 70** |

If no saved search with "Papers Since 2010" (or close variant) is found, score = 0 immediately.

## Verification Strategy

- `export_result.sh` queries `savedSearches` and `savedSearchConditions` tables in `zotero.sqlite`
- Tries to find the search by exact name, then case-insensitive, then partial match containing "2010"
- Extracts condition field names and values
- Checks if any condition value contains a year between 2009 and 2015
- `verifier.py` reads `/tmp/create_saved_search_result.json`

## Database Schema Reference

```sql
-- Saved searches
SELECT savedSearchID, savedSearchName FROM savedSearches WHERE libraryID = 1;

-- Search conditions
SELECT condition, operator, value
FROM savedSearchConditions
WHERE savedSearchID = <search_id>
ORDER BY searchConditionID;

-- Condition field reference (Zotero 7):
-- condition='date'     → publication date
-- condition='year'     → year component
-- operator='isAfter'  / 'isGreaterThan' / '>='
-- value='2009-12-31' / '2009' / '2010'
```

## Setup State

- 18 papers (10 classic 1905–1960 + 8 ML 2012–2020) seeded via `seed_library.py --mode all`
- No pre-existing saved searches (baseline count = 0)
- Zotero running and displaying all 18 papers
- Initial search count at `/tmp/initial_search_count`

## Edge Cases

- Agent creates saved search with name "Papers since 2010" (lowercase 's') → partial credit (25 pts, name is "close")
- Agent sets condition to "is before 2010" instead of "is after" → `has_year_threshold` passes but search would return wrong papers; verifier gives credit for having a date condition with a 2010 threshold even if operator is wrong (since we can't easily validate the logical direction from the DB alone)
- Agent creates the search but doesn't set any conditions → `has_conditions` = False, score = 40 pts max (fail)
- Zotero may store the date condition value in various formats: "2009", "2009-12-31", "2010", "2010-01-01" → export script extracts any 4-digit year between 2009–2015 from the value
