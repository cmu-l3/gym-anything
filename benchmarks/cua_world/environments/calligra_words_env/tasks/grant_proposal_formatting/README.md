# grant_proposal_formatting

## Overview
Format an NSF grant proposal to comply with PAPPG (Proposal & Award Policies & Procedures Guide) requirements by reading a requirements document and applying all formatting standards.

## Domain Context
- **Occupation**: Research Administrator / Grant Writer
- **Industry**: Higher education and research funding
- **Workflow**: Research administrators format grant proposals for faculty PIs according to funding agency requirements. NSF PAPPG has specific font, margin, section ordering, and formatting requirements that must be met for successful submission.

## Task Design Pattern
**Specification-Driven Discovery + Multi-feature Pipeline**: The agent must find and read the NSF formatting requirements on the Desktop, then apply multiple interacting formatting requirements (margins, fonts, heading hierarchy, tables, TOC, cover page).

## Goal
Format the unformatted NSF proposal to be fully compliant with PAPPG standards as described in the requirements document on the Desktop.

## Starting State
- Document: `/home/ga/Documents/nsf_proposal.odt` — complete NSF proposal with all sections (Cover Page through Biographical Sketch) as plain paragraphs, no formatting
- Requirements: `/home/ga/Desktop/nsf_formatting_requirements.txt` — NSF PAPPG formatting summary
- Calligra Words is open with the document loaded

## Success Criteria
1. Cover page title bold and >=14pt
2. Cover page elements centered (PI name, institution)
3. H1 section headings (>=5/7 main sections)
4. H2 subsection headings (>=5/8 subsections)
5. Body text justified (>=3/4 samples)
6. Font size >=11pt (>=2/3 samples)
7. Budget table with proper structure
8. Table of Contents present
9. Content preservation (>=6/8 keywords)
10. VLM visual verification

Pass threshold: 70%

## Verification Strategy
ODF XML parsing. Checks title formatting, paragraph alignment, heading styles, font sizes, table presence and content, TOC detection, and content preservation.

## Data Sources
- **Document content**: Grant proposal content structured per NSF PAPPG requirements. References cite real published papers in environmental engineering (Davis et al. 2009, Lehmann & Joseph 2015, Ahmad et al. 2014, etc.).
- **Formatting specification**: Based on actual NSF PAPPG formatting requirements.
- **Budget data**: Realistic budget structure following NSF conventions.

## Difficulty: very_hard
- Agent must discover the requirements file on the Desktop
- Multiple interacting requirements (font size, margins, heading hierarchy, cover page, budget table, TOC)
- Must understand section ordering conventions
- Must create a proper budget table from plain text data
- 10 independent verification criteria
