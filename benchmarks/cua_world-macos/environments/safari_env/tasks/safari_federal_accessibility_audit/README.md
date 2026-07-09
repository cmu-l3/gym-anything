# safari_federal_accessibility_audit

## Domain Context

Digital accessibility engineers and UX compliance consultants are frequently contracted by government agencies and their vendors to assess whether federal public-facing websites meet WCAG 2.1 AA and Section 508 requirements. Safari's built-in Web Inspector includes an **Audit** panel that runs automated accessibility checks — similar to axe-core or Lighthouse — and reports issues categorised as Errors, Warnings, and Comments. This is a platform-native tool that accessibility professionals use when auditing sites specifically for Safari's WebKit rendering engine, which differs from Chromium-based browsers.

## Goal

Use Safari's Web Inspector Audit panel to run accessibility audits on four federal government websites and document the findings in `~/Documents/federal_accessibility_audit.json`.

**Target sites**: `www.ssa.gov`, `www.medicare.gov`, `www.va.gov`, `www.benefits.gov`

## Occupation

**Accessibility Engineers / UX Compliance Consultants**  
Industry: Digital Consulting / Government Technology / Section 508 Compliance

## Difficulty: very_hard

The description gives only the professional goal. The agent must:
- Discover that Safari's Web Inspector contains an Audit tab
- Open Web Inspector for each target site via the Develop menu
- Run the Audit and wait for it to complete
- Record total issue count, the breakdown by type (Errors / Warnings / Comments), and at least 3 specific issue descriptions verbatim from the panel
- Produce a correctly structured JSON output

## Required Output

**File**: `~/Documents/federal_accessibility_audit.json`  
**Format**: JSON object keyed by domain (or a list of site objects):

```json
{
  "www.ssa.gov": {
    "total_issues": 47,
    "errors": 12,
    "warnings": 28,
    "comments": 7,
    "issues": [
      "Images are missing 'alt' text",
      "Form elements are missing associated labels",
      "Color contrast ratio does not meet WCAG AA requirements"
    ]
  },
  "www.medicare.gov": { ... },
  "www.va.gov": { ... },
  "www.benefits.gov": { ... }
}
```

The exact issue counts will vary based on page state and Safari version. Any nonzero count is valid as long as it reflects a genuine audit run.

## How to Access Safari's Audit Panel

The agent must discover this on its own. Hint embedded in task description: "Safari's built-in Web Inspector Audit tool (Audit tab in Web Inspector)". The Develop menu must be enabled (handled by `setup_task.sh`).

## Verification Strategy

| Criterion | Points | Details |
|---|---|---|
| ≥1 site entry found | 10 | At least one site object in output |
| ≥2 target sites visited in browser | 15 | History check on ssa.gov, medicare.gov, va.gov, benefits.gov |
| ≥1 site complete (total + breakdown + 3 descriptions) | 15 | Full data for at least one site |
| ≥3 sites complete | 30 | — |
| All 4 sites complete | 30 | — |
| **Pass threshold** | **70** | |

A site entry is "complete" when it has: a numeric `total_issues` count, at least one issue-type breakdown field (errors/warnings/comments), and at least 3 specific issue description strings of >5 characters each.

## Adversarial Robustness

- **Multi-site visit gate**: Score=0 if no target .gov sites visited — cannot fabricate audit results without loading the pages
- **Post-setup timestamp**: Output file must post-date task start
- **3-description minimum**: Prevents trivially minimal outputs

## Edge Cases

- Safari's Audit panel requires the page to finish loading before the audit runs reliably. Slow .gov sites may need extra wait time.
- The Audit tab appears in Safari's Web Inspector under the "Audit" label (distinct from the "Elements", "Console", "Network" tabs). Setup enables developer extras; the agent still needs to open Web Inspector (Develop → Show Web Inspector, or ⌥⌘I).
- Federal sites often use content delivery networks that serve different content by geography — issue counts may vary from run to run.
- The agent may record `total_issues` from the panel header ("47 Issues") and break it down from the sidebar groupings.

## Strategy Enumeration

| Strategy | Sites complete | Score | Pass? |
|---|---|---|---|
| Do-nothing | 0 | 0 | No |
| Visit 1 site, save partial output | ≤1 | ≤40 | No |
| Visit all 4, save minimal output (no descriptions) | 0 complete | ≤25 | No |
| Visit all 4, save complete output for 3 sites | 3 | 70 | Yes |
| Visit all 4, full output | 4 | 100 | Yes |
