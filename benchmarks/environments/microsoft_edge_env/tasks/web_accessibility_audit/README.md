# Web Accessibility Audit using Edge DevTools

## Overview

**Difficulty**: Very Hard
**Occupation Context**: Web Developers, UX Researchers, Accessibility Specialists
**Timeout**: 900 seconds | **Max Steps**: 120

This task simulates a real-world contract engagement: an accessibility consultant is hired by a government agency to audit two major government websites for WCAG 2.1 compliance using Edge's built-in DevTools (Lighthouse + Accessibility panel).

Web accessibility auditing is a core responsibility of web developers and UX specialists working with government clients, who are legally required under Section 508 and WCAG 2.1 to make their sites accessible. This task requires genuine knowledge of accessibility standards, DevTools tooling, and professional report writing.

---

## Task Description

The agent must:

1. **Navigate to ssa.gov** (Social Security Administration) and audit:
   - The homepage
   - At least 2 additional pages (e.g., a forms/benefits page, a login or help page)

2. **Navigate to irs.gov** (Internal Revenue Service) and audit:
   - The homepage
   - At least 2 additional pages (e.g., a filing page, a forms/publications page)

3. **Use Edge DevTools** to perform the accessibility audit:
   - Run **Lighthouse** audit (Accessibility category) on each page
   - Inspect the **Accessibility panel** in DevTools for specific violations
   - Check for: missing alt text, color contrast failures, keyboard navigation issues, missing ARIA labels, form element labeling

4. **Produce a comprehensive audit report** saved to:
   ```
   /home/ga/Desktop/accessibility_audit_report.txt
   ```

---

## What the Report Must Contain

The report should be a professional accessibility audit document that a government web team would actually use:

- Site name and URLs audited
- Lighthouse accessibility scores for each page
- Specific WCAG 2.1 success criteria violations found (e.g., "1.1.1 Non-text Content — 12 images missing alt text")
- Severity categorization: Critical / Serious / Moderate / Minor
- Recommended remediation for each category of issue
- Summary comparison between the two sites

**Minimum report length**: ~800 characters (a substantive document)

---

## Scoring (100 points)

| Criterion | Points | Details |
|-----------|--------|---------|
| Report exists and was created after task start | 10 | File at `/home/ga/Desktop/accessibility_audit_report.txt`, modified after task start |
| Both ssa.gov and irs.gov were visited (history) | 20 | New visits to both sites detected in browser history |
| Report names both sites explicitly | 10 | Both "ssa.gov"/"Social Security" and "irs.gov"/"Internal Revenue" appear in report |
| Report contains WCAG vocabulary | 20 | Terms: WCAG, accessibility, alt text, aria, contrast, etc. (≥4 terms) |
| Report contains Lighthouse scores | 15 | Numeric accessibility scores (e.g., "87", "92") mentioned in report |
| Report covers severity classification | 15 | Words "critical", "serious", or "moderate" appear in context of issues |
| Report is substantive (≥800 chars) | 10 | Report has enough content to be a real audit document |

**Pass threshold**: 65 points

---

## Why This Task is Hard

1. **DevTools expertise required**: Must know to open DevTools (F12), navigate to Lighthouse tab, run an accessibility audit, and interpret the results
2. **Multi-site, multi-page**: Must audit multiple pages across two different government sites
3. **Domain knowledge**: Must know WCAG 2.1 terminology, severity classifications, and remediation recommendations
4. **Report writing**: Must produce a professional, structured document — not just a screenshot dump
5. **No UI hand-holding**: The task description states the goal (audit report) but not the specific DevTools menus to click

---

## Occupation Context

Top users of Edge for this type of work (from occupation data):
- **Web Developers** — primary occupation; use browser DevTools daily for testing and debugging
- **UX Researchers** — evaluate websites for usability and accessibility compliance
- **Accessibility Specialists** — specialize in WCAG compliance auditing for government and enterprise clients
- **Computer and Information Systems Managers** — oversee compliance programs including Section 508

Government websites (ssa.gov, irs.gov) are legally required under **Section 508 of the Rehabilitation Act** and **WCAG 2.1 Level AA** to be accessible. Accessibility auditing is a growing professional field with significant economic activity.

---

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task metadata and verification criteria |
| `setup_task.sh` | Records baseline history counts, clears old report, launches Edge |
| `export_result.sh` | Queries browser history, reads report file, exports result JSON |
| `verifier.py` | Multi-criterion verification and scoring logic |
| `README.md` | This documentation |
