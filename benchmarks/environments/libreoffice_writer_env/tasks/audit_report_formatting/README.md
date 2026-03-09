# Internal Audit Report Professional Formatting

## Task Overview

**Occupation**: Internal Auditor / Chief Audit Executive
**Industry**: Financial Services / Banking / Corporate Governance
**Difficulty**: very_hard
**Application Feature Focus**: Bordered/shaded table for Executive Summary callout box, Heading 2 paragraph styles for findings, table cell background shading (XML-level), colored text for risk ratings, footer styling

---

## Domain Context

Internal audit reports follow the Institute of Internal Auditors (IIA) International Standards for the Professional Practice of Internal Auditing. A well-formatted audit report uses visual hierarchy to help executive stakeholders rapidly identify critical findings without reading the full narrative. Key formatting conventions:

- **Executive Summary in a callout box**: A bordered table cell isolates the executive narrative from body text, signaling its summary nature
- **Finding headings with numbered labels**: "Finding 1: [Title]" in Heading 2 style allows quick navigation and cross-referencing
- **Risk rating table with header shading**: Dark background on the header row of the risk matrix distinguishes column labels from data
- **Color-coded risk ratings**: Red for High, amber/yellow for Medium, green for Low text makes risk tiers immediately scannable
- **Professional footer**: "Internal Audit Report — NorthBridge Financial Group" in the footer identifies the report for retention filing

This task represents a CAE (Chief Audit Executive) or senior auditor applying professional polish to a report draft before it goes to the Audit Committee of the Board.

---

## Goal / End State

The agent must produce a formatted copy saved at:
**`/home/ga/Documents/audit_final.docx`**

The original draft at `/home/ga/Documents/audit_draft.docx` need not be preserved separately; saving to the new output path is sufficient.

The formatted report must satisfy all of the following:

1. **Executive Summary callout box**: The Executive Summary narrative is enclosed in a bordered single-cell (or merged) table, visually distinguishing it as a callout box
2. **Finding headings**: At least 4 of the 5 findings have their title formatted as "Finding N: [Title]" using Heading 2 style
3. **Risk table header shading**: The header row of the risk rating summary table has a dark fill (hex shade) in its cells — indicating column labels are visually distinct
4. **Risk rating colored text**: The risk rating values (High/Medium/Low) in the risk table use colored text (non-black) corresponding to severity
5. **Footer**: The footer on each page contains "Internal Audit Report"

---

## Source Document

`/home/ga/Documents/audit_draft.docx` — A Q3 2024 Internal Audit Report for NorthBridge Financial Group. Contains 5 findings:
- Finding 1: Access Control Deficiencies (High risk) — FFIEC/NIST controls
- Finding 2: Segregation of Duties Gaps (High risk) — SOX / COSO controls
- Finding 3: Vendor Due Diligence Failures (Medium risk) — OCC guidance
- Finding 4: Data Retention Policy Violations (Low risk) — SEC 17a-4
- Finding 5: IT Change Management Weaknesses (Medium risk) — COBIT 5/ITIL

**Intentional formatting deficiencies in the draft:**
- Executive Summary: plain paragraph text (not in a table/box)
- Finding headings: plain bold text (Normal style, not Heading 2)
- Risk table: "Table Grid" style but no header shading, no colored text
- No footer

---

## Verification Criteria

| # | Criterion | Points | Checker |
|---|-----------|--------|---------|
| 1 | `audit_final.docx` exists | 16 | File copy |
| 2 | Executive Summary in a bordered table cell | 16 | Scan `doc.tables` for cell containing "executive summary" |
| 3 | ≥4 of 5 finding headings with "Finding N:" prefix use Heading 2 | 16 | `para.style.name` + regex `Finding \d+:` |
| 4 | Risk table header row has dark background (XML `w:shd`/`w:fill`) | 16 | `row._element.xml` regex for fill color |
| 5 | Risk rating text (High/Medium/Low) has color (non-black XML `w:color`) | 16 | `para._element.xml` scan for `w:color` attributes |
| 6 | Footer contains "Internal Audit Report" | 16 | `section.footer` paragraph text |

**Pass threshold**: 65 points (≈4 of 6 criteria)

---

## Key Technical Details

- **Executive Summary box detection**: The verifier iterates `doc.tables`, then each cell, checking if cell text contains "executive summary" (case-insensitive). Any such cell counts as the callout box.
- **Finding heading pattern**: Regex `r'finding\s+\d+:'` (case-insensitive) identifies finding headings. Combined with `para.style.name.lower().startswith("heading 2")` for the style check.
- **Header row shading**: Inspects `table.rows[0]._element.xml` for XML patterns: `w:shd`, `w:fill`. A non-white, non-auto fill attribute indicates shading.
- **Colored text detection**: Inspects `para._element.xml` for `w:color` with `w:val` attribute that is not "000000" and not "auto". The verifier checks the risk rating row paragraphs.
- **IIA Standards referenced in content**: IIA Standard 2400 (Communicating Results), 2410 (Criteria for Communicating)

---

## Edge Cases / Potential Issues

1. **Executive Summary merged cell**: The agent might use a merged table (multiple rows merged into one) rather than a single-cell table. The verifier only checks that the cell text contains "executive summary" — it doesn't require a specific table shape.
2. **Risk table structure**: The draft has the risk table but without shading. The agent needs to add shading to the existing table's first row, not create a new table. If the agent creates a second table, the verifier will scan all tables and find any that match.
3. **Color format**: python-docx `w:color` values can be hex RGB (e.g., "FF0000" for red) or named colors. The verifier checks for presence of `w:color` XML elements that are not pure black.
4. **Heading 2 vs manual formatting**: The agent might bold and increase the font size of finding headings without applying Heading 2 style. This won't pass criterion 3.
