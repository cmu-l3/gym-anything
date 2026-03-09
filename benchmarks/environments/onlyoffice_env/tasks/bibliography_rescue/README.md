# Bibliography Rescue Task (`bibliography_rescue@1`)

## Overview

This task tests an agent's ability to perform detailed academic citation formatting work. The agent must convert a messy collection of 8 citations in mixed formats (MLA, incomplete entries, wrong capitalization) into properly formatted APA 7th edition bibliography entries.

## Scenario

**Context**: A graduate student is finalizing their thesis due tomorrow morning. They've collected citations from various sources—some from Google Scholar, some hand-typed from books, some from their advisor's email—all in inconsistent formats. The university requires strict APA 7th edition formatting.

**Problem**: The citations are a mess:
- Mixed formats (MLA style, incomplete information, inconsistent patterns)
- Author names in wrong format (full first names instead of initials)
- Article titles in Title Case instead of sentence case
- Missing italics on journal names and book titles
- Missing DOIs for journal articles
- Wrong punctuation patterns
- Not sorted alphabetically
- No hanging indents

**Goal**: Transform all 8 citations into proper APA 7th edition format before thesis submission.

## Task Requirements

The agent must:

1. **Fix author name format**: Convert to "LastName, F. M." format with proper punctuation
2. **Correct title capitalization**: Article/chapter titles in sentence case (only first word capitalized)
3. **Apply italics**: Italicize journal names and book titles
4. **Add missing information**: Include DOIs provided at bottom of document
5. **Fix punctuation**: Ensure proper periods, commas, parentheses per APA guidelines
6. **Sort alphabetically**: Order by first author's last name
7. **Apply hanging indents**: First line flush left, subsequent lines indented 0.5"
8. **Save document**: Ctrl+S to save changes

## Starting Document

The document contains:
- **References** header
- **8 messy citations** with various formatting errors
- **Missing information section** with DOIs to add
- **Instructions** section describing the task

### Example Citation Transformations

**Before** (Entry 1 - MLA style):