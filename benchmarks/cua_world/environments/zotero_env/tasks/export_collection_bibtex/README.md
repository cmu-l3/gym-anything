# Task: export_collection_bibtex

## Overview

A researcher preparing a manuscript submission needs to provide their bibliography in BibTeX format for their LaTeX document. The Zotero library already contains an "ML References" collection with 8 foundational deep learning papers. The task is to export this collection as a properly formatted `.bib` file to a specific location on the desktop.

## Target

- **Collection**: ML References (pre-created with 8 ML papers)
- **Output file**: `/home/ga/Desktop/ml_bibliography.bib`
- **Format**: BibTeX (`.bib`)

## Papers in "ML References" (8 total)

| Paper | Author | Year |
|-------|--------|------|
| Attention Is All You Need | Vaswani et al. | 2017 |
| BERT: Pre-training of Deep Bidirectional Transformers... | Devlin et al. | 2019 |
| Language Models are Few-Shot Learners | Brown et al. | 2020 |
| ImageNet Classification with Deep Convolutional Neural Networks | Krizhevsky et al. | 2012 |
| Deep Residual Learning for Image Recognition | He et al. | 2016 |
| Generative Adversarial Nets | Goodfellow et al. | 2014 |
| Deep Learning | LeCun, Bengio, Hinton | 2015 |
| Mastering the Game of Go with Deep Neural Networks and Tree Search | Silver et al. | 2016 |

## Task Description

1. In Zotero's left panel, locate the collection **"ML References"**
2. Right-click on **"ML References"**
3. Select **"Export Collection..."**
4. In the format dropdown, select **"BibTeX"**
5. Click **"OK"**
6. In the file save dialog, navigate to the Desktop (`/home/ga/Desktop/`)
7. Type the filename: **`ml_bibliography.bib`**
8. Click **"Save"**

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| File exists at `/home/ga/Desktop/ml_bibliography.bib` | 30 | Also checks `~/Desktop/` and `~/*.bib` as fallbacks |
| File contains valid `@article{...}` or `@inproceedings{...}` entries | 20 | At least 1 BibTeX entry |
| Author last names found: Vaswani, Devlin, Brown, Krizhevsky, He, Goodfellow, LeCun, Silver (5 pts each, max 30) | 30 | Case-insensitive search |
| File size ≥ 1500 bytes | 20 | BibTeX for 8 papers should be ~3-5KB |
| **Total** | **100** | **Pass threshold: 60** |

## Verification Strategy

- `export_result.sh` checks for the file at several possible paths (Desktop, home dir, Documents)
- Counts `@article` / `@inproceedings` / `@misc` entries via regex
- Searches for each expected author last name
- Reports file size
- `verifier.py` reads `/tmp/export_collection_bibtex_result.json`

## Database Schema Reference

The collection is pre-created in Zotero's DB:
```sql
-- Verify collection exists
SELECT collectionID, collectionName FROM collections
WHERE collectionName = 'ML References' AND libraryID = 1;

-- Verify items in collection
SELECT COUNT(*) FROM collectionItems WHERE collectionID = <id>;
```

## Setup State

- 8 ML papers seeded via `seed_library.py --mode ml_with_collection`
- "ML References" collection pre-created with all 8 papers
- Any pre-existing `ml_bibliography.bib` on the Desktop is deleted at setup
- Zotero running and displaying the library with "ML References" visible in the left panel

## Edge Cases

- Agent exports to wrong location (e.g., Documents/) → `file_exists` check fails, score 0
- Agent exports as wrong format (CSV, RIS) → has no `@` BibTeX entries, score ≤ 30
- Agent exports only some papers → fewer author names found, lower score
- Agent right-clicks "My Library" and exports entire library → file is larger but will still contain the required authors → passes (we don't enforce exactly 8 entries, only that required authors are present)
- Zotero's file dialog remembers last location → agent may need to navigate to Desktop if a different path is pre-selected
