# manuscript_import_cleanup

## Overview
Fix formatting errors in a Frankenstein manuscript that were introduced during an import process. The agent must identify and correct all errors using professional proofreading judgment.

## Domain Context
- **Occupation**: Proofreader / Copy Marker
- **Industry**: Publishing and editorial services
- **Workflow**: Proofreaders regularly receive manuscripts that have been converted between formats, introducing formatting artifacts. They must identify and fix all errors while preserving content.

## Task Design Pattern
**Error Injection**: The document is created with 5 types of deliberately injected formatting errors. The agent must diagnose which elements are wrong and fix them without an explicit error list.

## Goal
Fix all formatting errors in the imported Frankenstein manuscript. Chapter headings should be Heading 1, body text should be 12pt justified with consistent font, emphasized phrases should be properly italicized, and incorrectly bolded words should be un-bolded.

## Starting State
- Document: `/home/ga/Documents/frankenstein_manuscript.odt` — Frankenstein excerpt (Letters 1-4, Chapters 1-2) with 5 types of injected errors
- Calligra Words is open with the document loaded

### Injected Errors (documented in task.json)
1. **Wrong heading levels**: Letter 1 (H3), Letter 2 (plain paragraph), Letter 4 (H2), Chapter 1 (H3) — should all be H1
2. **Wrong font**: 4 paragraphs in Comic Sans MS — should be standard serif font
3. **Wrong alignment**: 3 paragraphs centered — should be justified
4. **Missing italic**: 5 phrases not italicized — should be italic ("Ancient Mariner", "Prometheus", "what can stop the determined heart", "paradise of my own creation", "tabula rasa")
5. **Incorrect bold**: 3 words incorrectly bolded — should not be bold ("supernatural", "electricity", "magnetism")

Note: Letter 3 and Chapter 2 are correctly formatted as H1 to make the task non-trivial (agent can't just select-all and apply H1).

## Success Criteria
1. All 6 chapter headings as Heading 1 (>=5/6)
2. No wrong-font paragraphs remaining (0/4 with Comic Sans)
3. Body text justified (>=2/3 samples)
4. Italic phrases restored (>=4/5)
5. Incorrect bold removed (<=1/3 still bold)
6. Consistent font size ~12pt (>=2/3 samples)
7. Content preservation (>=5/6 keywords)
8. VLM visual verification

Pass threshold: 70%

## Verification Strategy
ODF XML parsing. Checks heading outline levels, font names in style chain, paragraph alignment, italic/bold text properties, and font sizes.

## Data Sources
- **Document content**: Text from Mary Shelley's *Frankenstein; or, The Modern Prometheus* (1818), public domain via Project Gutenberg.
- **Error injection**: 5 error types documented in task.json metadata, programmatically constructed using odfpy styles.

## Difficulty: very_hard
- Agent must diagnose errors without being told what they are
- Must navigate multi-page document to find all errors
- Must understand professional manuscript formatting conventions
- Must distinguish correct formatting from errors (some headings are already correct)
- 8 independent verification criteria
