# Professional Services Agreement Finalization

## Task Overview

**Occupation**: Corporate Attorney / Transactional Lawyer
**Industry**: Legal Services / Corporate Law
**Difficulty**: very_hard
**Application Feature Focus**: Title formatting (centering, bold, font size), Heading 1 paragraph styles, inline bold (defined terms), table creation (signature block), footer with page number field

---

## Domain Context

Professional Services Agreements (PSAs) must meet law firm presentation standards before being sent to clients for execution. A raw draft arriving from a junior associate or a previous Word version often lacks consistent typographic treatment required by house style. This task represents a common document-finalization workflow in a corporate transactional practice: taking a plain-text draft and applying firm formatting standards to produce an execution-ready agreement.

Key formatting conventions that distinguish a finalized PSA:
- All-caps, centered, bold title at 14pt
- Each article/section heading uses a consistent paragraph style for easy navigation and TOC generation
- Defined terms in the Definitions article are typographically distinguished (bolded on first definition)
- Signature block presented as a two-column side-by-side layout (Party A | Party B)
- Footer includes the firm's confidentiality legend and auto-incrementing page numbers

---

## Goal / End State

The agent must produce a formatted copy of the PSA draft saved at:
**`/home/ga/Documents/psa_final.docx`**

The original draft at `/home/ga/Documents/psa_draft.docx` should not be the final output (the agent should save to the new path).

The finalized document must satisfy all of the following:

1. **Title**: "PROFESSIONAL SERVICES AGREEMENT" is centered, bold, and at least 13pt
2. **Section headings**: At least 7 of the 9 article headings (Definitions, Scope of Services, Fees and Payment, Intellectual Property, Confidentiality, Representations and Warranties, Limitation of Liability, Indemnification, General Provisions) use the built-in "Heading 1" paragraph style
3. **Defined terms**: In the Definitions article, at least 4 of the 6 defined terms ("Services", "Deliverables", "Confidential Information", "Intellectual Property Rights", "Force Majeure Event", "Effective Date") appear in bold when first defined
4. **Signature block**: The signature block is formatted as a 2-column table (one column per party) containing By, Name, Title, Date fields for each party
5. **Footer**: The footer includes the firm name/confidentiality legend ("Meridian Legal" or "CONFIDENTIAL") AND an auto-incrementing page number field

---

## Source Document

`/home/ga/Documents/psa_draft.docx` — A 9-article Professional Services Agreement between Vertex Analytics Corp. ("Client") and Meridian Data Solutions LLC ("Consultant"). The agreement covers data analytics consulting services with a $175,000 contract value.

**Intentional formatting deficiencies in the draft:**
- Title: 11pt, not bold, left-aligned (Normal style)
- Section headings: plain text (Normal style, not Heading 1)
- Defined terms: not bolded in Definitions section
- Signature block: plain text lines (not a table)
- No footer

---

## Verification Criteria

| # | Criterion | Points | Checker |
|---|-----------|--------|---------|
| 1 | `psa_final.docx` exists | 16 | File copy |
| 2 | Title: centered AND bold AND ≥13pt (all 3) | 16 | `para.alignment`, `run.bold`, `run.font.size.pt` |
| 3 | ≥7 of 9 section headings have "Heading 1" style | 16 | `para.style.name` check |
| 4 | ≥4 of 6 defined terms are bold in Definitions section | 16 | Run-level bold scan in Definitions context |
| 5 | Signature block is a 2-column table with sig keywords | 16 | `len(table.columns)==2`, keyword check for By/Name/Title/Date |
| 6 | Footer has firm name AND page number field | 16 | `section.footer` text + XML `w:fldChar`/`PAGE` check |

**Pass threshold**: 65 points (≈4 of 6 criteria)

---

## Key Technical Details

- **Title detection**: The verifier scans all paragraphs for text containing "PROFESSIONAL SERVICES AGREEMENT" (case-insensitive). The first match is evaluated for centering (`para.alignment == WD_ALIGN_PARAGRAPH.CENTER`), bold runs, and font size.
- **Signature table detection**: Any 2-column table whose combined text contains ≥3 of {"By:", "Name:", "Title:", "Date:"} is accepted as the signature block. Border styling is checked via XML but is not required for full credit.
- **Footer page number**: Detected by scanning `section.footer._element.xml` for "PAGE", "w:fldChar", or "w:instrText" tokens.
- **Defined terms bolding**: Scans paragraphs inside the Definitions section (between the "Definitions" heading and the next section heading) for runs containing each defined term, checks `run.bold`.

---

## Edge Cases / Potential Issues

1. **Defined terms with quotation marks**: The PSA draft uses standard ASCII double quotes. The verifier checks for both `"term"` patterns to handle smart quotes if Word converts them.
2. **2-column tables**: The agent might create a table with more columns (e.g., 3 or 4) for the signature block. Only 2-column tables are accepted for full credit. A table with more columns won't match.
3. **Heading 1 style name**: LibreOffice Writer's built-in heading style is "Heading 1" in python-docx. If the agent creates a custom style called "Section Heading" instead, the verifier won't recognize it.
4. **Title all-caps**: The title in the document is already in all-caps. The check is case-insensitive, so this works regardless.
