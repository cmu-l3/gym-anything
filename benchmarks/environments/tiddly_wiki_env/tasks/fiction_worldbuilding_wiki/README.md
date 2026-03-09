# fiction_worldbuilding_wiki

## Overview

**Occupation**: Poets, Lyricists and Creative Writers (Fantasy Fiction)
**Difficulty**: hard
**Domain**: World-Building / Fiction Writing Reference

A fantasy fiction writer building a world-building reference wiki for a novel series called "Shards of the Celestial War". This reflects how creative writers use note-taking tools for organizing plot lines, character arcs, world-building bibles, and research notes.

## Goal

Create 6 interconnected tiddlers forming a complete world-building wiki:

1. **Celestial War - World Overview** — World setting description; table of major factions: Faction | Alignment | Territory | Leader | Primary Goal; links to all other tiddlers
2. **Celestial War - Factions and Politics** — 4+ factions detailed; table: Faction | Type | Alignment | Military Strength | Key Resources | Internal Conflict
3. **Celestial War - Characters** — 5+ characters; table: Name | Faction | Role | Age | Special Power/Skill | Motivation | First Appears In
4. **Celestial War - Magic System** — Magic rules, source, costs; table: Magic Type | Source | Practitioners | Strength | Limitation/Cost
5. **Celestial War - Timeline** — Chronological world history; table: Era/Year | Event | Significance | Characters Involved | Impact on Present
6. **Celestial War - Glossary** — World-specific terms; table: Term | Category | Definition | First Mentioned In

All 6 tiddlers must be tagged `Fiction` and `CelestialWar`, contain `!!` headings, tables, and wikilinks. The Characters tiddler must have 5+ character rows in its table.

## Success Criteria

- All 6 tiddlers exist by exact title
- Each has `Fiction` and `CelestialWar` tags
- Characters tiddler has 5+ non-header table rows
- Each contains at least one wiki table
- Each has at least 100 words
- GUI saves confirmed in server log
- Score ≥ 60, found_count ≥ 4, fiction_tagged ≥ 4, gui_save = true

## Characters Table Requirement

The Characters tiddler must have at least 5 named characters as table rows. The export script counts non-header rows in the Characters tiddler (lines starting with `|` but not `|!`). 5+ rows = 8 pts; 3-4 rows = 4 pts; <3 rows = 0 pts.

## Verification Strategy

**Export script** (`export_result.sh`): Scans all 6 tiddlers. For Characters tiddler, counts non-header table rows. Tag normalization removes spaces/hyphens before checking `CelestialWar`.

**Verifier** (`verifier.py`): Multi-criterion scoring:
| Criterion | Points |
|-----------|--------|
| Each tiddler found (×6) | 8 pts each = 48 |
| Fiction tag (1/tiddler, cap 5) | 5 |
| CelestialWar tag (1/tiddler, cap 5) | 5 |
| Tables (2/tiddler, cap 10 → 5 tiddlers) | 10 |
| Wikilinks (1/tiddler, cap 6) | 6 |
| Characters: 5+ rows = 8, 3+ rows = 4 | 8 |
| Word count ≥100 (1/tiddler, cap 4) | 4 |
| GUI save | 14 |
| **Total** | **100** |

## TiddlyWiki Table Header Format

Header rows use `|! Column Name |! Column Name |` syntax. Non-header rows use `| data | data |`. The `count_table_rows` function counts lines starting with `|` that do NOT start with `|!`.

## Tag Normalization

`CelestialWar` tag: verifier normalizes by removing spaces/hyphens. So `Celestial War`, `celestial-war`, or `CelestialWar` all match.

## Anti-Gaming

Requires `gui_save_detected = true` to pass. Server log checked for: "Celestial", "Faction", "Character", "Magic", "Timeline", "Glossary", "World Overview".
