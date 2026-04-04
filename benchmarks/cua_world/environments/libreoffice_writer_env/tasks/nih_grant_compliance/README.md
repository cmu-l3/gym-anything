# NIH R01 Grant Compliance Reformatting

## Task Overview

**Occupation**: Grants Administrator / Life Scientist (Principal Investigator)
**Industry**: Biomedical Research / Academic Research Institution
**Difficulty**: very_hard
**Application Feature Focus**: Font/size reformatting, page margin adjustment, paragraph styles (Heading 1), header fields, hanging indent in References

---

## Domain Context

NIH grant applications submitted via SF424 (R&R) must comply with formatting requirements specified in Program Announcement PA-23-093. Non-compliance causes automatic administrative rejection by NIH before scientific review. Common compliance failures include:
- Disallowed typefaces (e.g., Times New Roman, Calibri)
- Font sizes below 11pt
- Margins narrower than 0.5 inches
- Missing or incorrect headers
- References without hanging indentation

This task represents a realistic pre-submission compliance check performed by a grants administrator or the PI before uploading to Grants.gov. The R01 application draft uses incorrect formatting throughout and must be corrected and saved as a new output file.

---

## Goal / End State

The agent must produce a reformatted copy of the R01 draft saved at:
**`/home/ga/Documents/r01_formatted.docx`**

The original draft at `/home/ga/Documents/r01_draft.docx` must NOT be modified.

The reformatted document must satisfy all of the following:

1. **Approved font**: All body text (non-heading paragraphs) uses Arial, Helvetica, Georgia, or Palatino Linotype (Liberation Sans is accepted as the Linux metric equivalent of Arial)
2. **Minimum font size**: Body text is 11pt or larger throughout
3. **Page margins**: All four margins (top, bottom, left, right) are 0.5 inches or less
4. **Heading styles**: The six major section headings — Abstract, Specific Aims, Research Strategy, Innovation, Approach, References — each use the built-in "Heading 1" paragraph style (not just manual bold)
5. **Hanging indent in References**: Each reference entry in the References section uses a 0.5-inch hanging indent (first line at left margin, continuation lines indented)
6. **Document header**: A header appears on every page reading (approximately): `Chen, S. — R01CA298471 — Tumor Microenvironment Immunotherapy`

---

## Source Document

`/home/ga/Documents/r01_draft.docx` — A draft R01 application for project "Modulating Tumor-Infiltrating Macrophage Polarization States to Enhance Anti-PD-1 Immunotherapy Response in Non-Small Cell Lung Cancer." The grant is by PI Dr. Sarah Chen (R01CA298471).

**Intentional formatting violations in the draft:**
- Font: Liberation Serif 10pt (wrong family, wrong size)
- Margins: 1.0 inch on all sides (wider than NIH 0.5" max)
- Section headings: plain bold text (not Heading 1 style)
- No document header
- References: no hanging indent

---

## Verification Criteria

| # | Criterion | Points | Checker |
|---|-----------|--------|---------|
| 1 | `r01_formatted.docx` exists | 14 | File copy |
| 2 | ≥50% of body runs use NIH-approved font | 14 | `run.font.name` loop |
| 3 | ≥60% of body runs are ≥11pt | 14 | `run.font.size.pt` loop |
| 4 | All 4 margins ≤ 0.5 inches (±60,000 EMU tolerance) | 14 | `doc.sections[0].{left,right,top,bottom}_margin` |
| 5 | ≥5 of 6 section headings have `Heading 1` style | 14 | `para.style.name` check |
| 6 | ≥60% of reference paragraphs have hanging indent | 14 | `para.paragraph_format.{first_line_indent, left_indent}` |
| 7 | Header contains "Chen" AND "R01CA298471" | 14 | `doc.sections[0].header.paragraphs` text |

**Pass threshold**: 65 points (5 of 7 criteria)

---

## Key Technical Details

- **Margin units**: python-docx returns margins in EMU (English Metric Units). 1 inch = 914,400 EMU; 0.5 inch = 457,200 EMU. A tolerance of 60,000 EMU (~0.065 inch) is applied.
- **Font compliance**: Liberation Sans (Linux substitute for Arial) is included in the approved set. Checking is case-insensitive.
- **Hanging indent detection**: A hanging indent has `first_line_indent < 0` (negative, pulls first line left) and `left_indent > 0` (positive, pushes continuation lines right). Alternatively, some implementations use `first_line_indent ≈ 0` with `left_indent > 0` relative layout.
- **Heading style check**: `para.style.name` must contain "Heading 1" (exactly, not "Heading 10").

---

## Regulatory Reference

NIH PA-23-093: "Research on Biobehavioral Mechanisms Linking Social Determinants of Health to Cancer Risk and Progression"
Format requirements: SF424 Application Guide Part II.2 (Formatting Guidelines):
- Approved fonts: Arial, Helvetica, Georgia, Palatino Linotype
- Minimum size: 11pt; Maximum: 6 lines/inch
- Margins: ≥ 0.5 inch all sides

---

## Edge Cases / Potential Issues

1. **Liberation Sans vs Arial**: The VM does not have Arial installed natively. The verifier accepts Liberation Sans. If the agent installs a font pack or changes to a Windows Arial, the check still passes.
2. **Margin direction**: NIH requires margins be *at least* 0.5 inch (≥0.5"). The task description follows this convention. The verifier checks that margins ≤ 0.5" only as a proxy for compliance (a stricter check isn't needed for this benchmark context).
3. **Header inheritance**: If the agent sets a header only on section 1, all other sections inherit it unless "different first page" is set. The verifier checks all sections.
4. **Saving as new file**: The task explicitly requires `r01_formatted.docx` at a different path. If the agent overwrites the draft and saves it as `r01_draft.docx`, the output file won't exist and score = 0.
