# hierarchical_reorganization

**Difficulty**: hard
**Timeout**: 720s | **Max steps**: 100

## Goal

Your Zotero library has an "Unsorted Import" collection containing 30 papers spanning nearly a century of research (1934–2021). Reorganize them into a proper hierarchical structure:

1. Create a top-level collection called **"Research Archive"**
2. Inside it, create four subcollections: **Pre-1960**, **1960-1999**, **2000-2010**, **Post-2010**
3. Move each paper to the subcollection matching its publication year
4. Delete the original **"Unsorted Import"** collection once all papers have been moved

Expected distribution: Pre-1960 (8 papers), 1960-1999 (10), 2000-2010 (7), Post-2010 (5)

## Success Criteria

- "Research Archive" collection exists at the top level
- All 4 decade subcollections exist inside it
- All 30 papers moved to the correct decade subcollection
- "Unsorted Import" collection no longer exists
