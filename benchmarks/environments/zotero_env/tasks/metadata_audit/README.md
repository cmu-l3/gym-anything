# metadata_audit

**Difficulty**: very_hard
**Timeout**: 900s | **Max steps**: 120

## Goal

You have a Zotero library containing 25 biology and medicine research papers. A data entry process introduced three categories of errors into 15 of these papers. Find and correct all errors:

1. **Wrong publication years** — 5 papers have years stored approximately 10 years off from the correct value. Use your knowledge of when these discoveries were made to identify and fix each one.
2. **Swapped author names** — 5 papers have the first and last name fields reversed for the first author. Identify each case and swap the names back to the correct order.
3. **Placeholder abstracts** — 5 papers have the abstract set to the placeholder text "Abstract not available". Replace each placeholder with the actual abstract for that paper.

The remaining 10 papers have no errors and should not be modified.

## Success Criteria

- All 5 year errors corrected
- All 5 author name swaps corrected
- All 5 placeholder abstracts replaced with real content
