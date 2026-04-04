# Task: add_reading_note

## Overview

A PhD student conducting a machine learning literature review needs to annotate a key paper with reading notes documenting its core contributions. This tests the ability to navigate a Zotero library, locate a specific paper, create a child note, and write structured annotation content.

## Target

- **Paper Title**: Attention Is All You Need
- **Author**: Vaswani et al.
- **Year**: 2017
- **Journal**: Advances in Neural Information Processing Systems (vol. 30)

## Task Description

1. Open Zotero (already running, library pre-loaded with 18 papers)
2. Locate the paper "Attention Is All You Need" in the main items list
3. Click on it to select it
4. In the right panel, click the **Notes** tab
5. Click **Add Note** to create a new child note
6. Write a reading note that includes ALL three required keywords:
   - `Transformer` (the architecture name)
   - `self-attention` (the key mechanism)
   - `translation` (the application domain)
7. The note must be at least 2–3 sentences (≥100 characters)

Notes save automatically as you type in Zotero.

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| Note attached to "Attention Is All You Need" | 30 | Must be child note of that specific paper |
| Note contains "Transformer" | 25 | Case-insensitive |
| Note contains "self-attention" (or "self attention") | 25 | Hyphen optional |
| Note contains "translation" | 10 | Any form: translation, translate, etc. |
| Note ≥ 100 characters | 10 | Encourages meaningful annotations |
| **Total** | **100** | **Pass threshold: 70** |

## Verification Strategy

- `export_result.sh` queries `itemNotes` table in `zotero.sqlite` for notes where `parentItemID` matches the target paper's ID
- Strips HTML tags from note content
- Checks for each required keyword (case-insensitive)
- `verifier.py` reads `/tmp/add_reading_note_result.json`

## Database Schema Reference

```sql
-- Zotero 7 note schema
-- itemNotes table:
--   itemID       INTEGER  (note's item ID)
--   parentItemID INTEGER  (the paper this note belongs to)
--   note         TEXT     (HTML-encoded note content)
--   title        TEXT     (auto-generated note title)

-- Finding the target paper:
SELECT i.itemID, v.value AS title
FROM items i
JOIN itemData d ON i.itemID = d.itemID
JOIN itemDataValues v ON d.valueID = v.valueID
WHERE d.fieldID = 1  -- title field
  AND v.value LIKE '%Attention Is All You Need%';

-- Finding child notes:
SELECT note FROM itemNotes WHERE parentItemID = <target_item_id>;
```

## Setup State

- Library seeded with 18 papers (10 classic + 8 ML) via `seed_library.py --mode all`
- No notes pre-existing on any paper
- Zotero is launched and displaying the full library
- Baseline note count recorded at `/tmp/initial_note_count`

## Edge Cases

- Agent might add a note to the wrong paper → score 0 (no note on target)
- Agent might write a note without the required keywords → partial score (30 pts)
- Agent might add note content via Edit > Add Note rather than right panel → both paths work in Zotero 7
- Zotero HTML-encodes note content (e.g., `<div>text</div>`) — export script strips tags before keyword matching
