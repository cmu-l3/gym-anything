# Task: legal_contract_styles

**Difficulty**: Very Hard
**Domain**: Legal
**Primary Occupation**: Lawyers, Document Management Specialists
**Application**: Apache OpenOffice Writer

---

## Overview

A draft commercial lease agreement was prepared by an outside contractor who did not follow the law firm's document formatting standards. All section headings and subsection headings were formatted using direct bold text (manual font size/weight overrides) instead of the proper "Heading 1" and "Heading 2" paragraph styles. The document also lacks a Table of Contents and page numbering in the footer.

The agent, acting as a senior paralegal, must:
1. Read the firm's formatting standards guide
2. Identify all incorrectly-formatted headings in the 10-section lease
3. Apply "Heading 1" style to all main section headings
4. Apply "Heading 2" style to all subsection headings
5. Insert an automatically-generated Table of Contents
6. Add page numbers to the footer
7. Save as `commercial_lease_final.odt`

This task is genuinely hard because the agent is NOT told which paragraphs need which style. The agent must audit the document, understand the heading hierarchy from context (numbered sections vs. numbered subsections), and apply the correct styles throughout.

---

## Real Data

The document uses realistic legal content based on California commercial real estate practice:
- **Landlord**: Pacific Properties LLC (fictitious but realistic California LLC)
- **Tenant**: Meridian Analytics Inc. (fictitious but realistic California tech company)
- **Property**: 4500 Technology Drive, Suite 200, Palo Alto, CA 94304 (real street)
- Lease terms, rent schedules, legal clauses based on standard California commercial lease provisions

---

## Starting State

- `/home/ga/Documents/draft_commercial_lease.odt` — draft with all headings using direct bold formatting (ODT `text:p` elements with bold automatic styles, NOT `text:h` elements with outline-level)
- `/home/ga/Documents/firm_standards.txt` — the firm's document formatting guide
- No `/home/ga/Documents/commercial_lease_final.odt` yet

---

## Expected End State

- `/home/ga/Documents/commercial_lease_final.odt` exists
- Has ≥ 9 paragraphs with `text:h text:outline-level="1"` (Heading 1 style)
- Has ≥ 18 paragraphs with `text:h text:outline-level="2"` (Heading 2 style)
- Contains `text:table-of-content` element (auto-generated TOC)
- Contains `text:page-number` field in styles.xml footer

---

## Verification Criteria

| Criterion | Points | How Checked |
|-----------|--------|-------------|
| Heading 1 applied to ≥9 main sections | 30 | Count `<text:h outline-level="1">` in content.xml |
| Heading 2 applied to ≥18 subsections | 30 | Count `<text:h outline-level="2">` in content.xml |
| Auto-generated TOC inserted | 25 | `text:table-of-content` in content.xml |
| Page numbers in footer | 15 | `text:page-number` in styles.xml or content.xml |
| **Total** | **100** | |
| **Pass threshold** | **70** | |

**GATE**: If `commercial_lease_final.odt` does not exist → score=0 immediately.

**Partial completion test**: An agent that applies heading styles but does NOT add TOC or footer can score at most 60 pts (fails). An agent that adds only TOC and footer but does not fix styles can score at most 40 pts (fails). The agent must do both heading styles AND at least one navigation element to pass.

---

## Planted Bugs (Starting State)

The draft_commercial_lease.odt has these specific formatting violations:
- 10 main section headings ("1. PARTIES" through "10. DEFAULT...") use `text:p` with `FakeH1` automatic style (bold 16pt) instead of `text:h outline-level="1"`
- 22 subsection headings ("1.1 Landlord" through "10.3 Attorney's Fees") use `text:p` with `FakeH2` automatic style (bold 13pt) instead of `text:h outline-level="2"`
- No `text:table-of-content` element
- No footer, no `text:page-number` field

---

## Schema Reference

ODT format (ZIP containing XML):
- `content.xml` — document body with paragraph/heading elements
- `styles.xml` — page layout, master pages, footer definitions
- Proper headings: `<text:h text:outline-level="1">Section Title</text:h>`
- Fake headings: `<text:p text:style-name="FakeH1">Section Title</text:p>`
