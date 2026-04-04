# Task: audit_report_fix

**Difficulty**: Very Hard
**Domain**: Government Property Management / Document Quality Control
**Primary Occupation**: Government Property Inspectors, Administrative Editors
**Application**: Apache OpenOffice Writer

---

## Overview

The Metro Nashville Department of General Services received a facility condition assessment report for the Howard Office Building (700 2nd Ave S, Nashville, TN) from an external inspector. Before the report can be officially filed in the records system, it must pass a formatting review against the department's document standards.

The submitted draft (`building_audit_draft.odt`) has **four distinct categories of formatting violations** that must all be corrected:

1. **Wrong heading levels**: All 10 subsection headings are formatted as Heading 3 (`text:outline-level="3"`) when the department standard requires Heading 2 (`text:outline-level="2"`) for all subsections
2. **Fake manual Table of Contents**: The document's TOC is a manually-typed block of `text:p` paragraphs — it will become outdated as headings are edited. An auto-generated TOC (`text:table-of-content` field) is required
3. **Red text in body paragraphs**: Three critical deficiency paragraphs in Section 5.1 have red text (`fo:color="#ff0000"`). The department's formatting policy requires all body text to be black
4. **No footer or page numbers**: The document has no footer section and no page number fields. Official filed reports must have page numbers in the footer

The agent must open the draft, fix all four categories of errors, and save the corrected document as `/home/ga/Documents/building_audit_final.odt`.

This task is genuinely hard because: the agent must independently identify all four types of errors (not just one); the heading level issue requires examining every subsection heading throughout a multi-section technical document; the red text issue is not visible unless the agent opens and inspects the document; and both the TOC fix and footer fix require using specific Writer features (Insert > TOC, Insert > Header/Footer > Page Numbers) rather than typing text.

---

## Real Data

The document uses realistic government building inspection content:
- **Property**: Howard Office Building, 700 2nd Avenue South, Nashville, TN 37210 (real street, Metro Nashville government area)
- **Department**: Metro Nashville Department of General Services (real government department)
- **Inspector**: Patricia Holloway, Property Inspector IV (fictitious but realistic title)
- **Document number**: FCA-2024-0117
- **Content**: Realistic facility condition assessment findings including HVAC, electrical, structural, plumbing deficiencies with dollar estimates consistent with real building repair costs

---

## Starting State

- `/home/ga/Documents/building_audit_draft.odt` — draft with 4 classes of formatting violations:
  - `text:outline-level="3"` for all 10 subsection headings (should be `"2"`)
  - Manual text TOC (NOT `text:table-of-content`)
  - 3 paragraphs with `fo:color="#ff0000"` (red text)
  - No `<style:footer` in styles.xml
- No `/home/ga/Documents/building_audit_final.odt` yet

---

## Expected End State

`/home/ga/Documents/building_audit_final.odt` exists and contains:
- ≥ 5 KB file size
- ≥ 10 `<text:h text:outline-level="2">` (all 10 subsections fixed to H2)
- 0 `<text:h text:outline-level="3">` remaining (all wrong H3s corrected)
- `text:table-of-content` element (auto-generated TOC, not manual text)
- Zero occurrences of `fo:color="#ff0000"` (all red text removed/changed to black)
- Footer with `text:page-number` field in styles.xml

---

## Document Structure (6 main sections, 10 subsections)

```
1. EXECUTIVE SUMMARY (H1)
   1.1 Assessment Overview      → fix H3 to H2
   1.2 Critical Findings Summary → fix H3 to H2
2. PROPERTY OVERVIEW (H1)
   2.1 Building Identification   → fix H3 to H2
   2.2 Physical Characteristics  → fix H3 to H2
   2.3 Occupancy and Use Profile → fix H3 to H2
3. STRUCTURAL AND ENVELOPE ASSESSMENT (H1)
   3.1 Foundation and Substructure → fix H3 to H2
   3.2 Structural Frame          → fix H3 to H2
   3.3 Exterior Facade and Windows → fix H3 to H2
4. MECHANICAL, ELECTRICAL, AND PLUMBING SYSTEMS (H1)
   4.1 HVAC Systems              → fix H3 to H2
   4.2 Electrical Distribution   → fix H3 to H2
   [4.3 Plumbing]                → also H3 to H2 (11th subsection)
5. DEFICIENCIES AND RECOMMENDATIONS (H1)
   5.1 Immediate Action Items    → fix H3 to H2; ALSO contains 3 red-text paragraphs
   5.2 12-Month Capital Repair Plan → fix H3 to H2
6. COST ESTIMATE SUMMARY (H1)
   6.1 Repair Cost Matrix        → fix H3 to H2
   6.2 Funding Recommendations   → fix H3 to H2
```

---

## Verification Criteria

| Criterion | Points | How Checked |
|-----------|--------|-------------|
| Heading 2 count ≥ 10 | 20 | Count `<text:h outline-level="2">` in content.xml |
| Heading 3 count = 0 | 15 | Count `<text:h outline-level="3">` in content.xml |
| Auto-generated TOC | 20 | `text:table-of-content` in content.xml |
| Red text removed | 20 | Count `fo:color="#ff0000"` in content.xml |
| Footer with page numbers | 25 | `style:footer` in styles.xml OR `text:page-number` in styles.xml |
| **Total** | **100** | |
| **Pass threshold** | **70** | |

**GATE**: If `building_audit_final.odt` does not exist or is < 5 KB → score=0 immediately.

**Partial calibration** (showing it's hard to pass without fixing headings):
- Headings fixed only (H2+H3): 35 pts (fails)
- Headings + TOC: 55 pts (fails)
- Headings + TOC + footer: 80 pts (passes)
- Headings + red fixed + footer: 80 pts (passes)
- Only TOC + footer, no heading fix: 45 pts (fails)
- Only red + footer, no heading fix: 45 pts (fails)

---

## Schema Reference

ODT format (ZIP containing XML):
- `content.xml` — document body with heading elements, paragraph styles
- `styles.xml` — page layout, master pages, footer definitions
- Wrong headings: `<text:h text:outline-level="3">Section Title</text:h>`
- Correct headings: `<text:h text:outline-level="2">Section Title</text:h>`
- Real TOC: `<text:table-of-content ...>`
- Red text automatic style: `<style:style ...><style:text-properties fo:color="#ff0000"/>`
- Page number in footer: `<text:page-number>` inside `<style:footer>`
