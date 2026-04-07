# board_minutes_sanitization

## Overview
Sanitize corporate board meeting minutes for public filing by removing confidential information according to a sanitization policy document.

## Domain Context
- **Occupation**: Corporate Secretary / Administrative Officer
- **Industry**: Corporate governance and SEC compliance
- **Workflow**: Corporate secretaries must sanitize board meeting minutes before filing with the SEC and distributing to shareholders. Sensitive categories (attorney-client privilege, acquisition targets, executive compensation, non-public projections, internal code names) must be removed while preserving all legitimate public-facing content.

## Task Design Pattern
**Contamination Injection**: The board minutes contain 5 categories of naturally embedded confidential information that the agent must identify and remove/redact using the sanitization policy as a guide. The contaminated items are not flagged — the agent must apply domain judgment.

## Goal
Apply the sanitization policy (on Desktop) to remove all confidential information from the board minutes while preserving legitimate content, document structure, and formatting.

## Starting State
- Document: `/home/ga/Documents/board_minutes_q4.odt` — complete Q4 2025 board minutes with 8 agenda sections, properly formatted with headings and justified body text
- Policy: `/home/ga/Desktop/sanitization_policy.txt` — sanitization categories (not specific items)
- Calligra Words is open with the document loaded

### Contaminated Items (documented in task.json)
1. **Attorney-client privilege**: Litigation probability assessment ("60% probability of adverse outcome") and settlement recommendation ("settling for $4.2 million")
2. **Acquisition target**: Company name ("CloudNest Systems") and deal terms ("$78 million acquisition")
3. **Executive compensation**: Specific figures ("$875,000" base salary, "$1.2 million" bonus, "50,000 shares" RSU)
4. **Non-public projection**: Preliminary unaudited revenue ("$412 million")
5. **Internal code name**: "Project Falcon" (3 occurrences) — should be replaced with "Advanced Analytics Platform"

### Legitimate Content (must be preserved)
- Board approval of capital expenditure budget ($200M)
- Quarterly dividend declaration ($0.35/share)
- CTO appointment
- Ernst & Young audit
- Annual meeting scheduling
- Cybersecurity improvements
- All section headings and document structure

## Success Criteria
1. Attorney-client privilege removed (phrases absent)
2. Acquisition target redacted (name and terms absent)
3. Executive compensation redacted (figures absent)
4. Non-public projections removed (unaudited figures absent)
5. Code names replaced ("Project Falcon" absent, "Advanced Analytics Platform" present)
6. Legitimate content preserved (>=6/8 phrases present)
7. Document structure preserved (>=6/8 headings present)
8. Content volume gate (document not over-truncated, >=60% of baseline)

Pass threshold: 75%

## Verification Strategy
Full-text search on extracted ODF document text. Checks presence/absence of specific phrases, heading structure, and document length.

## Data Sources
- **Document content**: Board meeting minutes following SEC filing conventions and corporate governance standards.
- **Contamination injection**: 5 categories of sensitive information documented in task.json metadata, naturally embedded in legitimate minute sections.
- **Sanitization policy**: Categories based on standard corporate governance practices for public company minute redaction.

## Difficulty: very_hard
- Agent must read and understand the sanitization policy (categories, not specific items)
- Must identify which specific content falls into each category using domain judgment
- Must make targeted surgical edits without breaking document structure
- Must replace code names with public names (not just delete)
- Must preserve all legitimate content while removing confidential items
- 8 independent verification criteria with 75% pass threshold
