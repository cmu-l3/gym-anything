# Task: organize_into_subcollections

## Overview

A researcher starting a deep learning literature review needs to create a hierarchical collection structure to organize 18 pre-loaded papers by subfield. This tests multi-step UI navigation: creating nested collections and assigning specific papers to each subcollection by recognizing author/title/year combinations.

## Target Structure

```
My Library
└── Deep Learning Survey          ← must be exact name
    ├── NLP Papers                ← subcollection under parent
    │   ├── Attention Is All You Need (Vaswani, 2017)
    │   ├── BERT: Pre-training... (Devlin, 2019)
    │   └── Language Models are Few-Shot Learners (Brown, 2020)
    └── Vision Papers             ← subcollection under parent
        ├── ImageNet Classification... (Krizhevsky, 2012)
        ├── Deep Residual Learning... (He, 2016)
        └── Generative Adversarial Nets (Goodfellow, 2014)
```

**Collection names are case-sensitive and must match exactly.**

## Task Description

1. Open Zotero (running, 18 papers pre-loaded, no collections)
2. Create top-level collection **"Deep Learning Survey"** (right-click "My Library" → New Collection)
3. Create subcollection **"NLP Papers"** under "Deep Learning Survey"
4. Create subcollection **"Vision Papers"** under "Deep Learning Survey"
5. Add these 3 papers to "NLP Papers":
   - "Attention Is All You Need" (Vaswani et al., 2017)
   - "BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding" (Devlin et al., 2019)
   - "Language Models are Few-Shot Learners" (Brown et al., 2020)
6. Add these 3 papers to "Vision Papers":
   - "ImageNet Classification with Deep Convolutional Neural Networks" (Krizhevsky et al., 2012)
   - "Deep Residual Learning for Image Recognition" (He et al., 2016)
   - "Generative Adversarial Nets" (Goodfellow et al., 2014)

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| "Deep Learning Survey" collection exists | 20 | Top-level, exact name |
| "NLP Papers" under "Deep Learning Survey" | 15 | Must be child of parent |
| "Vision Papers" under "Deep Learning Survey" | 15 | Must be child of parent |
| Each NLP paper correctly placed | 10 × 3 = 30 | Title-based matching |
| Each Vision paper correctly placed | 7 × 3 = 20 (max) | Title-based matching |
| **Total** | **100** | **Pass threshold: 60** |

If "Deep Learning Survey" does not exist, score = 0 immediately (nothing else possible).

## Verification Strategy

- `export_result.sh` queries `collections` and `collectionItems` tables
- Checks parent collection exists at top level (parentCollectionID IS NULL)
- Checks NLP/Vision subcollections have correct parent
- For each target paper, checks it appears in `collectionItems` for the correct subcollection
- Title matching is case-insensitive substring match

## Database Schema Reference

```sql
-- Collections
SELECT collectionID, collectionName, parentCollectionID
FROM collections WHERE libraryID = 1;

-- Items in a collection
SELECT ci.itemID, v.value AS title
FROM collectionItems ci
JOIN itemData d ON ci.itemID = d.itemID
JOIN itemDataValues v ON d.valueID = v.valueID
WHERE ci.collectionID = <coll_id> AND d.fieldID = 1;
```

## Setup State

- 18 papers (10 classic + 8 ML) seeded via `seed_library.py --mode all`
- No pre-existing collections (baseline count = 0)
- Zotero running and displaying all papers
- Baseline collection count at `/tmp/initial_collection_count`

## Difficulty

**very_hard** — 6 UI objects to create/populate across 2 levels, requires navigating left panel and finding specific papers by title/author.

## Edge Cases

- Agent creates "Deep Learning Survey" but with wrong capitalization → score 0 for parent, no subcollection points
- Agent adds papers to parent instead of subcollections → parent found (20 pts) but NLP/Vision paper checks fail
- Agent adds NLP papers to Vision and vice versa → 0 pts for paper placement
- Zotero allows a paper to be in multiple collections → extra placements don't hurt, only the correct subcollection is checked
