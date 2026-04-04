# Task: iq_validation_protocol

**Difficulty**: Very Hard
**Domain**: Pharmaceutical / Validation Engineering
**Primary Occupation**: Validation Engineers, Quality Assurance Specialists
**Application**: Apache OpenOffice Writer

---

## Overview

NovaBridge Pharmaceuticals, Inc. (Princeton, NJ) has just installed a Waters ACQUITY UPLC H-Class ultra-high-performance liquid chromatography system in its QC Laboratory (Room 214). Under 21 CFR Part 211 and USP <1058> requirements, the instrument must undergo Installation Qualification (IQ) before it can be used for any GMP-regulated analytical testing. IQ is the documented verification that the instrument has been installed correctly and meets the manufacturer's specifications.

The agent, acting as Senior Validation Engineer Dr. Rajiv Mehta, must:
1. Read the instrument reference file at `/home/ga/Documents/instrument_data.json` for system specifications, site details, 6 IQ test items, and validation team information
2. Create a complete, GMP-compliant IQ Protocol document in Apache OpenOffice Writer
3. Structure the document using proper Heading 1 and Heading 2 paragraph styles
4. Include an auto-generated Table of Contents
5. Add page numbers in the footer (required for regulatory submissions)
6. Create formatted test execution tables for the 6 IQ test items (each with Test ID, description, acceptance criteria, result, and pass/fail columns)
7. Save as `/home/ga/Documents/VAL-IQ-UPLC-2024-004.odt`

This task is genuinely hard because: the agent must interpret pharmaceutical validation context from JSON data; understand that IQ protocols have a specific regulatory structure (not a generic document); use proper Writer heading styles and table features; and produce a document dense enough to pass the paragraph count and table count thresholds.

---

## Real Data

The instrument data uses realistic specifications from actual Waters ACQUITY UPLC H-Class documentation:
- **Instrument**: Waters ACQUITY UPLC H-Class (model 186007959, serial G18UPA003M)
- **Modules**: QSM (flow 0.01–2.0 mL/min), SM-FTN (injection 0.1–50 µL), CM-A (4–90°C), TUV detector (190–700 nm)
- **Company**: NovaBridge Pharmaceuticals, Inc. (fictitious but realistically modeled)
- **Address**: 600 College Road East, Princeton, NJ 08540
- **Document number**: VAL-IQ-UPLC-2024-004
- **Regulatory refs**: 21 CFR Part 211, USP <1058>, ICH Q2(R1), FDA 2015 Guidance

---

## Starting State

- `/home/ga/Documents/instrument_data.json` — full instrument data with 6 IQ tests, acceptance criteria, team contacts
- No `/home/ga/Documents/VAL-IQ-UPLC-2024-004.odt` yet

---

## Expected End State

`/home/ga/Documents/VAL-IQ-UPLC-2024-004.odt` exists and contains:
- ≥ 5 KB file size
- Auto-generated Table of Contents (`text:table-of-content` in content.xml)
- ≥ 5 `<text:h text:outline-level="1">` sections (e.g., Purpose & Scope, Regulatory References, Instrument Description, IQ Test Procedures, Signature Page)
- ≥ 6 `<text:h text:outline-level="2">` subsections (e.g., per-module specs, per-test-ID entries)
- ≥ 3 `<table:table>` tables (e.g., module specifications table, test execution tables for IQ-001 through IQ-006)
- Footer with page numbers (`text:page-number` field)
- ≥ 25 paragraphs of body text
- Mentions Waters/ACQUITY and IQ-specific terms (acceptance criteria, installation qualification, firmware, 21 CFR)

---

## Required IQ Protocol Sections (from instrument_data.json)

Standard pharmaceutical IQ document structure:
1. **Purpose and Scope** — what this IQ covers (instrument, location, regulatory basis)
2. **Regulatory References** — 21 CFR 211, USP <1058>, ICH Q2(R1), etc.
3. **Instrument Description** — modules, serial numbers, asset tag (table of components)
4. **IQ Test Procedures** — 6 test items (IQ-001 through IQ-006) each with acceptance criteria
5. **Results and Deviations** — pass/fail summary, deviation log
6. **Approvals / Signature Page** — validation engineer, lab manager, QA director signatures

---

## Verification Criteria

| Criterion | Points | How Checked |
|-----------|--------|-------------|
| Table of Contents present | 20 | `text:table-of-content` in content.xml |
| ≥ 5 Heading 1 sections | 20 | Count `<text:h outline-level="1">` in content.xml |
| ≥ 6 Heading 2 subsections | 15 | Count `<text:h outline-level="2">` in content.xml |
| ≥ 3 Tables present | 20 | Count `<table:table` in content.xml |
| Footer / page numbers | 15 | `text:page-number` in styles.xml or content.xml |
| Document length ≥ 25 paragraphs | 5 | Count `<text:p` in content.xml |
| Instrument name and IQ terms | 5 | Text search in document body |
| **Total** | **100** | |
| **Pass threshold** | **70** | |

**GATE**: If `VAL-IQ-UPLC-2024-004.odt` does not exist or is < 5 KB → score=0 immediately.

**Partial completion scenarios**:
- TOC + H1 + H2 + Tables (no footer, no content check) = 75 pts = passes (requires all structural elements)
- Structure without tables = max 60 pts (fails — tables are critical for IQ protocols)
- Tables only (no headings, no TOC) = max 27 pts (fails)

---

## Schema Reference

ODT format (ZIP containing XML):
- `content.xml` — document body
- `styles.xml` — page layout, footer definitions

JSON data file: `/home/ga/Documents/instrument_data.json`
- `.instrument` — name, serial numbers, modules with specs
- `.site` — company name, address, lab name
- `.validation_team` — engineer, lab manager, QA director contacts
- `.iq_requirements` — document number, 6 test items with acceptance criteria, regulatory references
