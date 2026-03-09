# it_knowledge_base

## Overview

**Occupation**: Computer User Support Specialist
**Difficulty**: hard
**Domain**: IT Support Documentation

A computer support specialist must build a structured IT troubleshooting knowledge base for their team using TiddlyWiki. This reflects the real use of knowledge base software by support teams for documenting solutions and researching fixes for complex issues.

## Goal

Create 6 interconnected tiddlers forming a complete IT support knowledge base:

1. **IT Support - Master Index** — Hub listing all guides with a table of issue categories/links/resolution times; links to all 5 other tiddlers
2. **IT Support - Network Connectivity** — Guide with sections: Symptoms, Common Causes, Diagnostic Steps (numbered), Solutions, When to Escalate; includes a commands table
3. **IT Support - Slow Performance** — Same structured guide format; includes a performance metrics table
4. **IT Support - Printer Problems** — Structured guide with a printer error code table
5. **IT Support - Email Configuration** — Guide for IMAP/SMTP setup; includes an email protocol settings table
6. **IT Support - Quick Reference Commands** — Reference sheet with 3+ tables comparing Windows and Linux/Mac commands for file ops, network diagnostics, and process management

All 6 tiddlers must be tagged `IT-Support`, contain `!!` headings, tables, and wikilinks.

## Success Criteria

- All 6 tiddlers exist by exact title
- Each has `IT-Support` tag
- Each contains at least one wiki table
- Troubleshooting guides contain symptom/solution content
- Each has at least 100 words
- TiddlyWiki server log confirms GUI saves
- Score ≥ 60, found_count ≥ 4, it_tagged ≥ 4, gui_save = true

## Verification Strategy

**Export script** (`export_result.sh`): Scans for each of the 6 tiddlers. For each, checks tags (case-insensitive for `IT-Support`, `it-support`, `itsupport`), headings, tables, links, word count, and checks for symptom/solution keywords.

**Verifier** (`verifier.py`): Multi-criterion scoring:
| Criterion | Points |
|-----------|--------|
| Each tiddler found (×6) | 8 pts each = 48 |
| IT-Support tag (1/tiddler, cap 6) | 6 |
| Tables (2/tiddler, cap 12) | 12 |
| Headings (1/tiddler, cap 6) | 6 |
| Structured guides (symptoms+solutions) | 4 |
| Wikilinks (1/tiddler, cap 6) | 6 |
| Word count ≥100 (1/tiddler, cap 4) | 4 |
| GUI save | 14 |
| **Total** | **100** |

## TiddlyWiki Wikitext Reference

- Numbered lists: `# item 1`, `# item 2`
- Bullet lists: `* item`
- Tables: `|! Col |! Col |` header row, `| data | data |` data rows
- Headings: `!! Section Title`, `!!! Subsection`
- Wikilinks: `[[IT Support - Master Index]]`

## Anti-Gaming

Requires `gui_save_detected = true` to pass. Server log pattern checked for: "IT Support", "Network", "Printer", "Email", "Performance", "Quick Reference".

## Edge Cases

- Tag `IT-Support` has a hyphen; verifier checks for `it-support`, `it support`, or `itsupport` (normalized) in the tags field
- All 6 tiddlers must be tagged — partial tagging gives partial credit
