# regulatory_compliance_report

## Overview
Format a Phase I Environmental Site Assessment report to comply with ASTM E1527-21 standards by reading a formatting specification document and applying all requirements.

## Domain Context
- **Occupation**: Environmental Compliance Specialist / Brownfield Redevelopment Specialist
- **Industry**: Environmental consulting and regulatory compliance
- **Workflow**: Preparing ESA reports for regulatory filing requires strict adherence to ASTM formatting standards. Consultants receive raw draft reports and must format them per specification before client delivery.

## Task Design Pattern
**Specification-Driven Discovery**: The agent must locate and read a formatting specification file on the Desktop, understand all interrelated requirements, and apply them systematically to the document. No explicit list of formatting actions is provided in the task description.

## Goal
Format the unformatted Phase I ESA report (plain text, no styles) to comply with all requirements in the ASTM E1527-21 formatting specification placed on the Desktop.

## Starting State
- Document: `/home/ga/Documents/phase1_esa_report.odt` — complete ESA report text with 8 standard sections, all as plain paragraphs (no heading styles, no bold, no TOC, no tables)
- Specification: `/home/ga/Desktop/esa_formatting_spec.txt` — formatting requirements (margins, fonts, headings, TOC, tables, page numbering)
- Calligra Words is open with the document loaded

## Success Criteria
1. Title formatted (bold, >=16pt)
2. Project name formatted (bold)
3. At least 6/8 ESA section headings as Heading 1
4. At least 5/9 subsection headings as Heading 2
5. Body text justified (>=3/5 samples)
6. Body font size >=11pt (>=3/5 samples)
7. Table of Contents present
8. At least 1 formatted table
9. Content preservation (>=6/8 keywords)
10. VLM visual verification

Pass threshold: 70%

## Verification Strategy
ODF XML parsing via `calligra_verification_utils.py`. Verifier copies the .odt file from the VM, unzips content.xml and styles.xml, and checks heading styles, text formatting, alignment, TOC presence, and table existence.

## Data Sources
- **Document content**: Structured per ASTM E1527-21 standard section requirements (Executive Summary, Introduction, Site Description, Records Review, Site Reconnaissance, Interviews, Evaluation, Conclusions). Content follows standard ESA report structure and terminology.
- **Formatting specification**: Based on ASTM E1527-21 formatting conventions used in professional practice.
- **Error injection**: None — document is intentionally unformatted (all plain paragraphs).

## Difficulty: very_hard
- Agent must discover the spec file on the Desktop (not told which formatting to apply)
- Must read and understand 8 interrelated formatting requirements
- Must apply heading hierarchy, text formatting, TOC, and tables through GUI
- 10 independent verification criteria
- No step-by-step instructions provided
