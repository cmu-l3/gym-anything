# tag_and_search_pipeline

**Difficulty**: hard
**Timeout**: 600s | **Max steps**: 80

## Goal

You have a Zotero library with 20 systems papers in a "Reading Queue" collection. Six papers are pre-tagged **"priority"** to indicate they need review. Your job is to triage them by era and create a usable saved search:

1. Tag each **pre-2010 priority paper** with `review-now`
2. Tag each **2010-or-later priority paper** with `review-later`
3. Create a saved search named **"Review Now"** that filters for items tagged `review-now`
4. Export the papers in that saved search as BibTeX to `/home/ga/Desktop/review_now.bib`

## Success Criteria

- 4 pre-2010 priority papers tagged `review-now`
- 2 post-2010 priority papers tagged `review-later`
- Saved search "Review Now" exists with a tag condition for `review-now`
- `/home/ga/Desktop/review_now.bib` exists and is non-empty
