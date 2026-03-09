# Fix Accessibility Violations Task

**Difficulty**: 🟡 Medium  
**Skills**: Web accessibility, ARIA, semantic HTML, React, WCAG compliance  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Fix WCAG accessibility violations in a React component based on an audit report. The task simulates a real-world scenario where a development team receives accessibility audit findings and must remediate them to achieve compliance.

## Scenario

Your team's web application failed an accessibility audit. The QA team identified 4 critical WCAG violations in the `DataTable.jsx` component that prevent screen reader users from properly navigating the content. These must be fixed before the government contract renewal deadline.

## Expected Workflow

1. Open and read `audit_report.md` to understand violations
2. Open `src/components/DataTable.jsx`
3. Fix all 4 violations:
   - Replace `<div>` sort control with semantic `<button>` element
   - Add descriptive `aria-label` to button
   - Add `<thead>` with `<th scope="col">` headers
   - Add `<caption>` to table
4. Save the file

## Verification

Checks for:
1. Semantic `<button>` element (not `<div>`)
2. Button has descriptive `aria-label` mentioning "sort"
3. Table has `<thead>` with `<th scope="col">` elements
4. Table has `<caption>` or `aria-label`

**Pass Threshold**: 90% (all 4 fixes applied correctly)

## Why This Matters

- Accessibility compliance is legally required in many industries
- Screen reader users rely on semantic HTML and ARIA
- WCAG 2.1 Level AA is a common regulatory requirement
- Teaches developers to write inclusive, standards-compliant code