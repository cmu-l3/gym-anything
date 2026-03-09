# Task: bcp_document_create

**Difficulty**: Very Hard
**Domain**: Risk Management / Business Continuity
**Primary Occupation**: Business Continuity Planners, Risk Managers
**Application**: Apache OpenOffice Writer

---

## Overview

Meridian Logistics Partners, LLC (Weehawken, NJ) is a third-party logistics provider with 312 employees and $84M in annual revenue operating across three facilities in NJ and PA. Following an insurance audit, leadership has mandated a formal ISO 22301-compliant Business Continuity Plan (BCP) document be created before the end of Q1 2024.

The agent, acting as Risk Management Director Tomasz Wierzbicki, must:
1. Read the company reference file at `/home/ga/Documents/company_info.json` to gather all company data, key personnel, critical systems (with RTO/RPO), and identified risk events
2. Create a complete, professionally formatted BCP document in Apache OpenOffice Writer
3. Structure the document using proper Heading 1 and Heading 2 paragraph styles (not bold text)
4. Include a Table of Contents
5. Add page numbers in the footer
6. Incorporate all required ISO 22301 sections, a recovery time objective table, and an emergency contact list
7. Save as `/home/ga/Documents/Meridian_BCP_2024.odt`

This task is genuinely hard because the agent must: read and interpret structured JSON data, understand ISO 22301 BCP document structure, use proper Writer formatting styles (not direct formatting), insert auto-generated navigation elements, and synthesize a multi-section professional document.

---

## Real Data

The company uses realistic data modeled on actual 3PL operations:
- **Company**: Meridian Logistics Partners, LLC (fictitious but realistically modeled NJ 3PL)
- **HQ**: 1201 Harbor Boulevard, Weehawken, NJ 07086
- **Locations**: Weehawken HQ (42,000 sqft), Edison Warehouse (68,000 sqft), Allentown Hub (55,000 sqft)
- **Key personnel**: COO Kathleen Ogundimu, VP IT Priya Sundaram, Dir. Operations Marcus Delacruz, HR Manager Aisha Fernandez
- **IT systems**: Oracle TMS Cloud (RTO 4h), Manhattan Associates WMS (RTO 8h), SAP S/4HANA (RTO 24h), Microsoft 365 (RTO 4h)
- **Document number**: MLP-BCP-2024-001
- **Regulatory frameworks**: ISO 22301, NIST SP 800-34, SOC 2 Type II

---

## Starting State

- `/home/ga/Documents/company_info.json` — full company data file with personnel, systems, risks
- No `/home/ga/Documents/Meridian_BCP_2024.odt` yet

---

## Expected End State

`/home/ga/Documents/Meridian_BCP_2024.odt` exists and contains:
- ≥ 5 KB file size (substantial document content)
- A Table of Contents (auto-generated, using `text:table-of-content` in ODT XML)
- ≥ 6 `<text:h text:outline-level="1">` sections (main BCP sections with Heading 1 style)
- ≥ 8 `<text:h text:outline-level="2">` subsections (Heading 2 style)
- ≥ 2 `<table:table>` tables (e.g., RTO/RPO table, emergency contacts table)
- Footer with page numbers (`text:page-number` field or `<style:footer` in styles.xml)
- ≥ 30 paragraphs of body text
- Document mentions company name and BCP-specific terminology

---

## Required BCP Sections (from company_info.json)

The `bcp_requirements.required_sections` field specifies 8 sections:
1. Purpose and Scope
2. Roles and Responsibilities
3. Risk Assessment and Business Impact Analysis
4. Recovery Strategies
5. Emergency Response Procedures
6. Communication Plan
7. IT Disaster Recovery
8. Testing and Maintenance

---

## Verification Criteria

| Criterion | Points | How Checked |
|-----------|--------|-------------|
| Table of Contents present | 20 | `text:table-of-content` in content.xml |
| ≥ 6 Heading 1 sections | 20 | Count `<text:h outline-level="1">` in content.xml |
| ≥ 8 Heading 2 subsections | 15 | Count `<text:h outline-level="2">` in content.xml |
| ≥ 2 Tables present | 15 | Count `<table:table` in content.xml |
| Footer / page numbers | 15 | `text:page-number` in styles.xml or content.xml |
| Document length ≥ 30 paragraphs | 10 | Count `<text:p` in content.xml |
| Company name and BCP terms present | 5 | Text search in document body |
| **Total** | **100** | |
| **Pass threshold** | **70** | |

**GATE**: If `Meridian_BCP_2024.odt` does not exist or is < 5 KB → score=0 immediately.

**Partial completion examples**:
- TOC + H1 + H2 + Tables (no footer, no length) = 70 pts = passes (barely)
- Structural elements only, no footer or length = max 70 (borderline)
- Footer only, no structure = max 15 pts (fails)
- An empty or near-empty file = gate fail at 0

---

## Schema Reference

ODT format (ZIP containing XML):
- `content.xml` — document body with paragraphs, headings, tables
- `styles.xml` — page layout, master pages, footer definitions
- Proper headings: `<text:h text:outline-level="1">Section Title</text:h>`
- Tables: `<table:table table:name="...">`
- TOC: `<text:table-of-content ...>`
- Page number field: `<text:page-number>`

JSON data file: `/home/ga/Documents/company_info.json`
- `.company` — name, address, locations
- `.key_personnel` — titles, emails, phone numbers for 5 contacts
- `.critical_systems` — 5 systems with RTO/RPO hours and criticality
- `.risk_events` — 5 risk scenarios with probability/impact
- `.bcp_requirements` — document number, required sections list, regulatory frameworks

---

## Edge Cases

- The agent must use **Writer paragraph styles** (Heading 1, Heading 2) not direct bold formatting
- The TOC must be the Writer auto-generated type (`text:table-of-content`), not a manually typed list
- Tables must use Writer's table feature (`table:table` elements), not tab-separated text
- Page numbers must use the Writer field mechanism (`text:page-number`), not static text "1"
