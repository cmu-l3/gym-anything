# citation_qa_export

**Difficulty**: very_hard
**Timeout**: 900s | **Max steps**: 120

## Goal

You have 20 CS theory papers tagged **"cite-in-paper"** that need to be exported as a clean BibTeX file. Before exporting, fix two categories of metadata problems:

1. **Empty journal/venue fields** — 3 papers are missing their publication venue (journal or conference name). Fill in the correct venue for each paper.
2. **Duplicate entries** — 3 papers each appear twice in the library (6 extra items). Merge each duplicate pair so only one copy of each remains.

After fixing all issues, export the cite-in-paper collection as BibTeX to `/home/ga/Desktop/references.bib`. The exported file should contain 17 entries (14 original clean papers + 3 fixed papers) with no duplicate citekeys.

## Success Criteria

- All 3 empty journal/venue fields filled with correct values
- All 3 duplicate pairs merged (20 items → 17 items)
- `/home/ga/Desktop/references.bib` exported with entries for all cite-in-paper items
- No duplicate citekeys in the BibTeX file
