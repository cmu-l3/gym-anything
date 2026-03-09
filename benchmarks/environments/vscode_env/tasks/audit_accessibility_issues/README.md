# VSCode Accessibility Audit Task (`audit_accessibility_issues@1`)

## Overview

This task tests an agent's ability to systematically identify accessibility violations in a web application codebase and document them for remediation. The agent must search through HTML and JSX files to find images without proper alt text, use VSCode's search and inspection features to distinguish between intentional and problematic cases, and create a structured report of violations. This represents essential code quality work required for WCAG 2.1 AA compliance and inclusive software development.

## Rationale

**Why this task is valuable:**
- **Accessibility Compliance:** Addresses legal requirements (ADA, Section 508) and inclusive design principles
- **Code Quality Auditing:** Teaches systematic codebase analysis for specific patterns
- **Pattern Recognition:** Distinguishes between intentional exceptions and violations (e.g., `alt=""` vs missing `alt`)
- **Search Mastery:** Requires advanced search features (regex, include/exclude patterns, search editor)
- **Documentation Skills:** Tests ability to organize findings into actionable reports
- **Real-World Urgency:** Represents common scenario when QA or accessibility audits flag compliance issues before release

**Skill Progression:** This task bridges basic search functionality with advanced pattern matching and systematic code quality work, preparing agents for compliance-driven development workflows.

## Task Details

**Difficulty**: 🟡 Medium  
**Skills**: Advanced search, regex, accessibility knowledge, documentation  
**Duration**: 300 seconds  
**Steps**: ~60

## Expected Workflow

1. Open Search panel (Ctrl+Shift+F)
2. Enable regex mode
3. Search for images without alt: `<img(?![^>]*alt=)[^>]*>`
4. Filter to `**/*.{jsx,tsx,html}` files
5. Review results in Search Editor
6. Distinguish decorative images (alt="") from violations
7. Search for unlabeled buttons and inputs
8. Create `ACCESSIBILITY_AUDIT.md` in workspace root
9. Document findings with file paths and line numbers
10. Categorize by violation type

## Verification

Checks for:
1. **Report exists** (20%): ACCESSIBILITY_AUDIT.md created with substantial content
2. **Structure** (15%): Proper markdown with headers, lists, summary
3. **Coverage** (35%): Identifies major violation categories and files
4. **Accuracy** (20%): Does not flag decorative images (alt="") as violations
5. **Specificity** (10%): Includes file paths and/or line numbers

**Pass Threshold**: 70% (requires identifying majority of violations accurately)

## Seeded Violations

The workspace contains:
- **5 images without alt attributes** (genuine violations)
- **3 images with `alt=""`** (decorative - should NOT be flagged)
- **2 icon buttons without aria-labels**
- **3 form inputs without associated labels**

## Files Structure
