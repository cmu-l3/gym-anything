# Clinical Trial Protocol Safety Amendment

## Task Overview

**Occupation**: Medical Writer / Regulatory Affairs Specialist
**Industry**: Pharmaceutical Research / Clinical Development
**Difficulty**: very_hard
**Application Feature Focus**: Header field editing (version and date), body text replacement (stopping rule), addition of new list item (exclusion criterion), new section insertion with Heading 2 style, table row addition (version history)

---

## Domain Context

When a clinical trial protocol is amended — typically in response to new safety data, regulatory feedback, or interim analysis results — the medical writing team must produce a formal Protocol Amendment document. Under ICH E6(R2) Good Clinical Practice guidelines and FDA 21 CFR 312.32, protocol amendments affecting subject safety must be implemented before enrollment resumes, and a clean amendment document must be submitted to the IRB/IEC and regulatory authority.

A Protocol Amendment requires:
- Updating the version number and date in all header/metadata fields
- Revising the specific safety stopping rule that triggered the amendment
- Adding the new exclusion criterion identified from safety analysis
- Adding a new protocol section describing the enhanced safety monitoring plan
- Appending a new row to the Version History table (Appendix A)

This task represents the medical writing step: given Protocol v1.0, produce Protocol v2.0 (Amendment 1) incorporating all changes mandated by a fictional cardiac safety concern.

---

## Goal / End State

The agent must produce an amended protocol saved at:
**`/home/ga/Documents/protocol_v2.docx`**

The source protocol at `/home/ga/Documents/protocol_v1.docx` should not be modified.

Protocol v2.0 must incorporate all of the following:

1. **Version header update**: All occurrences of "Version 1.0" in headers/body updated to "Version 2.0", and the date updated from "14 January 2024" to "15 March 2024"
2. **Updated stopping rule**: The safety stopping rule changed from "two (2) or more" cases of Grade 3+ cardiac AEs to "one (1) or more" (more conservative threshold)
3. **New exclusion criterion**: A new entry added to the Exclusion Criteria section: patients with QTc interval > 450 ms at screening are to be excluded
4. **New Section 9.4**: A new subsection headed "9.4 Cardiac Safety Monitoring Plan" (Heading 2 style) added to Section 9 (Safety Monitoring), describing 12-lead ECG assessments at specified timepoints
5. **Version history update**: A new row added to the Version History table in Appendix A documenting Version 2.0, dated 15 March 2024, with a brief description of Amendment 1 changes

---

## Source Document

`/home/ga/Documents/protocol_v1.docx` — A Phase II randomized double-blind placebo-controlled clinical trial protocol for study HELI-CARD-201, evaluating Heliogenin-A vs. placebo in patients with NYHA Class II-III heart failure. Principal Investigator: Dr. Marcus Holloway, MD, PhD.

**Protocol v1.0 content:**
- Version: "Version 1.0 | 14 January 2024" in header
- Section 7: Inclusion/Exclusion Criteria (numbered list, 10 exclusion criteria)
- Section 9: Safety Monitoring and Reporting, with stopping rule: "two (2) or more cases of Grade 3 or higher cardiac adverse events"
- Appendix A: Version History table with one row (v1.0, 14-Jan-2024)
- References: ICH E6(R2), 21 CFR 312.32, CTCAE v5.0, EU CTR 536/2014

---

## Verification Criteria

| # | Criterion | Points | Checker |
|---|-----------|--------|---------|
| 1 | `protocol_v2.docx` exists | 14 | File copy |
| 2 | Header/document contains "Version 2.0" and "15 March 2024" (or "2024-03-15") | 14 | Full doc text scan + header text check |
| 3 | New stopping rule "one (1) or more" is present in body text | 14 | `full_text` contains "one (1) or more" or "one or more" near "cardiac" |
| 4 | Old stopping rule "two (2) or more" is NOT present in cardiac context | 14 | `full_text` does NOT contain "two (2) or more" near stopping rule context |
| 5 | QTc exclusion criterion present (contains "qtc" + "450" or "470") | 14 | `full_text.lower()` contains "qtc" and ("450" or "470") |
| 6 | New Section 9.4 heading and "12-lead ECG assessment" content present | 14 | `para.style.name` for "9.4" heading + ECG content text |
| 7 | Version history table has a new row for Version 2.0 | 14 | Scan tables for row containing "2.0" and "2024" and "amendment" |

**Pass threshold**: 65 points (5 of 7 criteria)

---

## Key Technical Details

- **Header text**: python-docx `doc.sections[0].header.paragraphs` contains the header text. The verifier checks if "Version 2.0" appears in the header OR in the document body (some agents may update only one).
- **Stopping rule context**: The verifier searches for "two (2) or more" within a window around "stopping rule" or "cardiac" in the full document text. Pure text replacement is expected; the verifier checks absence of the old string in context.
- **Section 9.4 Heading**: `para.style.name.lower().startswith("heading 2")` and `"9.4" in para.text` (or `"cardiac safety" in para.text.lower()`).
- **Version history table**: The verifier iterates `doc.tables`, looking for a table where any row contains ("2.0" AND ("march" or "03" or "2024") AND ("amendment" or "safety")).
- **ICH E6(R2) reference**: International Council for Harmonisation of Technical Requirements for Pharmaceuticals for Human Use, Guideline for Good Clinical Practice E6(R2).

---

## Edge Cases / Potential Issues

1. **Version number ambiguity**: "Version 2.0" might appear in the body text as a reference to the new version. The verifier treats any occurrence as satisfying criterion 2.
2. **QTc threshold**: The stopping criterion uses 450 ms (typical threshold for men). Some agents may use 470 ms (threshold for women). The verifier accepts both values.
3. **Section 9.4 style**: If the agent adds the heading as plain bold text without applying Heading 2, criterion 6 (heading style) won't pass, but the ECG content check is a separate sub-check. The verifier gives partial credit if ECG content is present but heading style is wrong.
4. **Old stopping rule vestige**: If the agent adds the new "one (1) or more" rule but doesn't remove the old "two (2) or more" rule, criterion 4 will fail. Both replacement AND deletion are required.
