# gdd_wiki_setup

## Overview

**Occupation**: Video Game Designer
**Difficulty**: hard
**Domain**: Game Design Documentation

A video game designer must build a comprehensive Game Design Document (GDD) wiki for an indie project called "Echoes of the Void" using TiddlyWiki. This reflects the real industry practice of using personal wikis to maintain living design documentation for game projects.

## Goal

Create 6 interconnected tiddlers forming a complete GDD wiki:

1. **Echoes of the Void - GDD Hub** — Master hub with game concept overview, a table of all GDD sections, and wikilinks to all other tiddlers
2. **Echoes of the Void - Core Mechanics** — Gameplay loop description with a mechanics comparison table (3+ mechanics)
3. **Echoes of the Void - Character Roster** — Character profiles table with 3+ characters
4. **Echoes of the Void - World Design** — World description with areas/levels table
5. **Echoes of the Void - Story and Narrative** — Plot and story acts table
6. **Echoes of the Void - Technical Requirements** — Platform/spec table

All 6 tiddlers must be tagged `GDD` and `EchoesOfTheVoid`, contain TiddlyWiki headings (`!!`), tables (`|`), and `[[wikilinks]]` to each other.

## Success Criteria

- All 6 tiddlers exist by exact title
- Each tiddler has both `GDD` and `EchoesOfTheVoid` tags
- Each tiddler contains at least one wiki table
- Each tiddler contains wikilinks to other tiddlers
- Each tiddler has at least 80 words
- TiddlyWiki server log confirms GUI saves (not direct file edits)
- Score ≥ 60, found_count ≥ 4, gdd_tagged ≥ 4, gui_save = true

## Verification Strategy

**Export script** (`export_result.sh`): Python inline script scans `/home/ga/mywiki/tiddlers/` for each required tiddler by exact title match (with fallback to title field search). For each found tiddler, extracts tags, checks for headings (`^!!`), tables (`^\|`), wikilinks (`[[`), and counts words. Also checks TiddlyWiki server log for GUI save events.

**Verifier** (`verifier.py`): Multi-criterion scoring:
| Criterion | Points |
|-----------|--------|
| Each tiddler found (×6) | 8 pts each = 48 |
| GDD tag (1/tiddler, cap 5) | 5 |
| EchoesOfTheVoid tag (1/tiddler, cap 5) | 5 |
| Tables (2/tiddler with table, cap 12) | 12 |
| Wikilinks (1.5/tiddler, cap 9) | 9 |
| Word count ≥80 (1/tiddler, cap 7) | 7 |
| GUI save | 14 |
| **Total** | **100** |

## TiddlyWiki File Format Reference

Tiddlers are stored as `.tid` files in `/home/ga/mywiki/tiddlers/`. File format:
```
title: <title>
tags: <tag1> <tag2>
created: <timestamp>
modified: <timestamp>

<body text using TiddlyWiki wikitext>
```

Tables use pipe syntax: `|! Header |! Header |` (header), `| cell | cell |` (data).
Headings: `!! H2`, `!!! H3`. Wikilinks: `[[Tiddler Title]]`.

## Anti-Gaming

The TiddlyWiki server logs all saves: `syncer-server-filesystem: Dispatching 'save' task: <title>`. Direct `.tid` file edits do not appear in this log. The verifier requires `gui_save_detected = true` to pass.

## Edge Cases

- Tiddler filenames sanitize `:`, `*`, `?`, `"`, `<`, `>`, `|`, `/`, `\` → `_`; hyphens and spaces are preserved
- Tags with spaces must be quoted in the tags field: `tags: GDD EchoesOfTheVoid` (space-separated, no quotes needed for single-word tags)
- Agent must use the TiddlyWiki web GUI at http://localhost:8080 (no authentication required)
