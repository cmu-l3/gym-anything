# Structural Engineering Inspection Report Formatting

## Task Overview

**Occupation**: Licensed Structural Engineer (PE) / Building Inspector
**Industry**: Architecture and Engineering / Construction
**Difficulty**: very_hard
**Application Feature Focus**: Heading 1 paragraph styles for report sections, observation data converted to 3-column tables, calculation data converted to 4-column tables, Caption paragraph style for figure captions, bordered table with PE stamp/certification block

---

## Domain Context

Structural engineering inspection reports submitted to building departments, owners, or insurance carriers must follow professional presentation standards required by the National Council of Structural Engineers Associations (NCSEA) and state licensing boards. A PE (Professional Engineer) stamp in a formal table block, standardized observation tables, and captioned figures are standard requirements for reports that will be used in permit applications or litigation proceedings.

Key formatting requirements:
- **Observations as tables**: Each structural observation in a tabular format (Location | Deficiency Description | Recommended Action) enables side-by-side review and sorting
- **Calculation tables**: Engineering calculations in a parameter/value/unit/code reference 4-column format for auditability
- **Figure captions**: Figures referenced in the report use Word's Caption paragraph style (or consistent "Figure N:" prefix format) for cross-reference field generation
- **PE Certification block**: The engineer's certification statement enclosed in a formal bordered table with the PE license number — required format for official engineering documents in Texas (Board Rule 137.63)

This task represents a structural PE (or their document specialist) converting a rough field notes draft into a properly formatted engineering report ready for client delivery and permit application.

---

## Goal / End State

The agent must produce a formatted report saved at:
**`/home/ga/Documents/inspection_report.docx`**

The source draft at `/home/ga/Documents/inspection_draft.docx` need not be preserved.

The formatted report must satisfy all of the following:

1. **Section headings**: At least 5 of the 7 major sections (Introduction, Scope of Assessment, Building Description, Structural Observations, Structural Calculations, Conclusions and Recommendations, Professional Engineer Certification) use the built-in "Heading 1" paragraph style
2. **Observation tables**: At least 4 of the 7 observations (OBS-001 through OBS-007) are formatted as 3-column tables with columns for Location, Deficiency/Observation, and Recommended Action (rather than plain text paragraphs)
3. **Calculation tables**: At least 2 of the 3 calculations are formatted as 4-column tables with columns for Parameter, Value, Unit, and Code Reference
4. **Figure captions**: At least 4 of the 5 figure captions use either the Word "Caption" paragraph style or a consistent "Figure N:" prefix format
5. **PE Certification block**: The PE certification statement ("I hereby certify...") and PE license number (TX-78234) are enclosed in a bordered table (at least 1 visible border side)
6. **PE License in certification**: The license number TX-78234 appears somewhere in the PE certification table or nearby text

---

## Source Document

`/home/ga/Documents/inspection_draft.docx` — A structural inspection report for Riverside Office Complex (1234 Commerce Drive) by PE Michael T. Caldwell (PE License TX-78234, Civil Engineering).

**7 Structural Observations (OBS-001 through OBS-007):**
1. OBS-001: Critical — Column E-4, 2nd floor: transverse cracking with rebar exposure (ACI 318-19 §26.12)
2. OBS-002: High — Beam-column joint B-7, 3rd floor: diagonal shear cracking (ACI 318-14 §R18.8)
3. OBS-003: High — Exterior cladding spalling at Grid Line C between floors 1-2 (ACI 301-16 §5.3.7)
4. OBS-004: Moderate — Floor beam deflection at Column Grid D-5/D-6 (AISC 360-22 §L3)
5. OBS-005: Moderate — Foundation wall crack at northeast corner, Grid A-1 (ACI 318-19 §R22.6)
6. OBS-006: Minor — Mechanical equipment pad: minor corner cracking (ASCE 7-22 §13.3)
7. OBS-007: Minor — Secondary beam at Level 2 Grid F-3: surface rust (AISC 303-22 §M3)

**3 Structural Calculations:**
1. Column E-4 Axial Capacity (ACI 318-19 §22.4)
2. Punching Shear Check at D-3 (ACI 318-19 §22.6)
3. Equipment Pad Deflection (ACI 318-19 §24.2)

**5 Figure Captions:**
- Figure 1–5 referencing field photographs and structural drawings

**PE Certification block**: Plain paragraph text in the draft — must be enclosed in a bordered table.

---

## Verification Criteria

| # | Criterion | Points | Checker |
|---|-----------|--------|---------|
| 1 | `inspection_report.docx` exists | 14 | File copy |
| 2 | ≥5 of 7 section headings have Heading 1 style | 14 | `para.style.name` check for each heading keyword |
| 3 | ≥4 of 7 observations are 3-column tables with OBS-NNN identifiers | 14 | `doc.tables` scan: `len(table.columns)==3` + OBS label in cell text |
| 4 | ≥2 of 3 calculation tables are 4-column tables | 14 | `doc.tables` scan: `len(table.columns)==4` + "Parameter"/"Value" header |
| 5 | ≥4 of 5 figure captions use Caption style or "Figure N:" prefix | 14 | `para.style.name` == "Caption" OR `para.text.lower().startswith("figure ")` |
| 6 | PE certification in bordered table containing TX-78234 | 14 | `doc.tables` scan for "TX-78234" in cell text + border XML check |
| 7 | "I hereby certify" statement present in document | 14 | `full_text` contains "i hereby certify" |

**Pass threshold**: 65 points (5 of 7 criteria)

---

## Key Technical Details

- **3-column observation table detection**: Verifier iterates `doc.tables`, selects tables with exactly 3 columns, checks if any cell in the table contains an "OBS-" prefix or observation number pattern.
- **4-column calculation table detection**: Tables with exactly 4 columns where header row contains "Parameter" or "Value" or "Code Reference".
- **Caption style**: python-docx `para.style.name == "Caption"` or `"caption" in para.style.name.lower()`. Fallback: `para.text` matches `r'^Figure \d+'` regex.
- **PE Certification border**: Checks `table._element.xml` for XML border elements (`w:tblBorders`, `w:tcBorders`) with non-nil values. A single-cell bordered table (standard PE stamp format) is expected.
- **License number TX-78234**: Must appear in the cell text of the PE certification table to confirm the certified engineer's identity.

---

## Regulatory Reference

- **ACI 318-19**: Building Code Requirements for Structural Concrete (American Concrete Institute)
- **ASCE 7-22**: Minimum Design Loads and Associated Criteria for Buildings and Other Structures
- **AISC 360-22**: Specification for Structural Steel Buildings
- **Texas Board of Professional Engineers Rule 137.63**: Engineering document signing and sealing requirements

---

## Edge Cases / Potential Issues

1. **OBS table column count**: Some agents may create a 4-column table for observations (adding a "Severity" column). The verifier requires exactly 3 columns for the primary detection; a 4-column table won't match criterion 3.
2. **Merged cells in calculation tables**: If the agent creates a calculation table with merged cells (e.g., for multi-value parameters), the column count might report differently. The verifier checks `len(table.columns)` which counts unique column positions.
3. **Figure caption placement**: The agent might add "Figure N:" text directly in the body paragraph rather than as a separate captioned paragraph. The verifier accepts either "Caption" style paragraphs OR paragraphs whose text starts with "Figure ".
4. **PE table placement**: The PE certification block might be placed before the conclusions or at the end of the document. The verifier scans all tables in the document regardless of position.
