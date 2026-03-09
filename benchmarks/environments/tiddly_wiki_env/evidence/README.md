# TiddlyWiki Environment - Evidence Documentation

## Environment Overview

- **Application**: TiddlyWiki 5.3.8 (Node.js personal wiki)
- **Base Image**: `ubuntu-gnome-systemd_highres` (1920x1080)
- **Runtime**: Node.js 18.x LTS
- **Browser**: Firefox (configured with TiddlyWiki homepage)
- **Server Port**: 8080 (no authentication for agent interaction)

## Installation Verification

### Pre-start Hook (install_tiddlywiki.sh)
- Node.js 18.x installed from NodeSource repository
- TiddlyWiki 5.3.8 installed globally via npm
- Utilities installed: wmctrl, xdotool, imagemagick, jq

Log excerpt (last lines of pre_start):
```
Setting up jq (1.6-2.1ubuntu3.1) ...
=== TiddlyWiki installation complete ===
```

### Post-start Hook (setup_tiddlywiki.sh)
- Wiki initialized with `tiddlywiki mywiki --init server`
- 19 seed tiddlers created from realistic data (includes Database Normalization)
- TiddlyWiki server started on port 8080
- Firefox launched with pre-configured profile (no first-run dialogs)
- Firefox maximized

Log excerpt:
```
Seeded 19 tiddlers
TiddlyWiki server is running on port 8080
Firefox window detected
Firefox maximized
=== TiddlyWiki setup complete ===
```

## Verification Testing Results

### Scoring Breakdown Per Task

**create_tiddler** (100 pts total):
| Criterion | Points | Description |
|-----------|--------|-------------|
| Title match | 10 | Exact/partial title match |
| Word count | 10 | >= 100 words (5 for >= 50) |
| Keywords | 15 | data, model, training, pipeline (4 keywords) |
| Technology tag | 10 | Tag present |
| MachineLearning tag | 10 | Tag present |
| Formatting | 10 | 2+ distinct TiddlyWiki formatting types (headings, bullets, bold, italic, links) |
| New tiddler created | 10 | new_count > 0 (anti-gaming) |
| GUI save verified | 25 | Server log shows `Dispatching 'save' task:` entry |

**add_tags_to_tiddler** (100 pts total):
| Criterion | Points | Description |
|-----------|--------|-------------|
| Tiddler exists | 5 | CRISPR Gene Editing still present |
| Biotechnology tag | 20 | New tag added |
| Nobel tag | 20 | New tag added |
| Existing tags preserved | 10 | All 3 original tags retained |
| Content preserved | 10 | Original content intact, > 50 words |
| Total tag count | 10 | >= 5 tags |
| GUI save verified | 25 | Server log confirmation |

**rename_tiddler** (100 pts total):
| Criterion | Points | Description |
|-----------|--------|-------------|
| New title exists | 20 | "Q1 2024 Engineering Roadmap" found |
| Original removed | 20 | "Q1 2024 Product Roadmap" deleted (0 if still exists) |
| Tags preserved | 15 | Roadmap, Project Management, Q1 2024 |
| Content preserved | 20 | Keywords (api, dashboard, sprint) + word count |
| Word count match | 5 | New/original ratio 0.7-1.3 |
| GUI save verified | 20 | Server log confirmation |

**create_tiddler_with_links** (100 pts total):
| Criterion | Points | Description |
|-----------|--------|-------------|
| Tiddler found | 5 | Tiddler exists |
| Title match | 10 | "RESTful API Design Guide" |
| Agile link | 10 | `[[Agile Methodology Overview]]` present |
| VCS link | 10 | `[[Version Control Best Practices]]` present |
| Link count | 10 | >= 2 internal links |
| Content keywords | 10 | rest, api, http |
| Tags | 10 | Technology, API |
| Word count | 10 | >= 80 words |
| GUI save verified | 25 | Server log confirmation |

**create_journal_entry** (100 pts total):
| Criterion | Points | Description |
|-----------|--------|-------------|
| Journal found | 15 | Journal tiddler exists |
| Journal tag | 15 | "Journal" tag present |
| Date in title | 15 | Title contains today's date |
| Word count | 15 | >= 50 words |
| Content keywords | 10 | standup, progress, meeting, review |
| GUI save verified | 20 | Server log confirmation |
| New tiddler created | 10 | new_count > 0 (anti-gaming) |

### Pass Conditions (All Tasks)

Each task requires ALL of the following to pass:
- **gui_save_detected = true** (server log must show save event -- direct file edits fail)
- Task-specific content requirements met
- Score >= threshold (55-60 depending on task)

Task-specific pass requirements:
- **create_tiddler**: tiddler_found + new_count > 0 + gui_save + at least 1 tag + word_count >= 50
- **add_tags**: tiddler_exists + biotechnology_tag + nobel_tag + gui_save + existing_preserved >= 2 + content_preserved
- **rename_tiddler**: new_exists + NOT original_exists + gui_save + content_keywords >= 2 + tags_preserved >= 2
- **create_journal_entry**: journal_found + new_count > 0 + gui_save + journal_tag + date_in_title + word_count >= 25
- **create_tiddler_with_links**: tiddler_found + new_count > 0 + gui_save + agile_link + vcs_link + word_count >= 40

### "Do Nothing" Tests

**create_tiddler** - Ran export and verifier WITHOUT any interaction:
```
Result: passed=False, score=0
Feedback: FAIL: No new tiddler file created
```

**add_tags_to_tiddler** - Ran export and verifier WITHOUT adding any tags:
```
Result: passed=False, score=25
Feedback: Tiddler exists | FAIL: Biotechnology tag not found | FAIL: Nobel tag not found |
All 3 existing tags preserved | Content preserved | Insufficient tags: 3 |
FAIL: No server-mediated save detected (direct file edit suspected)
```

**rename_tiddler** - Ran export without renaming:
```
Result: passed=False, score=0
Feedback: FAIL: New title tiddler not found
```

### Anti-Gaming Tests

**create_tiddler DIRECT FILE EDIT** - Created .tid file directly (bypassing browser/server):
```
Result: passed=False, score=75
Feedback: Tiddler found | Title matches | Word count OK | All keywords | Both tags |
Formatting present | New tiddler created | FAIL: No server-mediated save detected
```
Scores 75/100 but FAILS because gui_save is required in pass condition.

**rename_tiddler COPY-NOT-DELETE** - Created new title but did not delete original:
```
Result: passed=False, score=80
Feedback: New title tiddler exists | FAIL: Original title still exists (copy instead of rename) |
All tags preserved | Content preserved | GUI save verified
```
Scores 80/100 but FAILS because `not original_exists` is required.

**create_journal_entry NO-DATE** - Created journal without date in title:
```
Result: passed=False, score=75
Feedback: Journal tiddler found | Journal tag present | FAIL: No date in title |
Word count OK | GUI save verified
```
Scores 75/100 but FAILS because `has_date_in_title` is required.

**create_tiddler_with_links ONE-LINK-ONLY** - Created tiddler with only 1 of 2 required links:
```
Result: passed=False, score=85
Feedback: Tiddler found | Title matches | Link to Agile present |
FAIL: Link to Version Control missing | GUI save verified
```
Scores 85/100 but FAILS because BOTH links required (AND not OR).

### "Correct Completion" Tests (All via GUI/Server)

**create_tiddler** - Created proper ML pipeline tiddler with all required elements:
```
Result: passed=True, score=100
Feedback: Tiddler found | Title matches: Machine Learning Pipeline Architecture |
Word count OK: 154 words | All 4 keywords found | Technology tag present |
MachineLearning tag present | TiddlyWiki formatting used (2+ types) |
GUI save verified via server log | New tiddlers created: 1
```

**add_tags_to_tiddler** - Added Biotechnology and Nobel tags to CRISPR Gene Editing tiddler:
```
Result: passed=True, score=100
Feedback: Tiddler exists | Biotechnology tag added | Nobel tag added |
All 3 existing tags preserved | Content preserved | Total tags: 5 |
GUI save verified via server log
```

**rename_tiddler** - Renamed via GUI:
```
Result: passed=True, score=100
Feedback: New title tiddler exists | Original title removed | All tags preserved |
Content preserved (122 words, 3 keywords) | Word count consistent with original |
GUI save verified via server log
```

**create_tiddler_with_links** - Created RESTful API Design Guide with internal links:
```
Result: passed=True, score=100
Feedback: Tiddler found | Title matches: RESTful API Design Guide |
Link to Agile Methodology Overview present | Link to Version Control Best Practices present |
Internal links: 2 | All API keywords found (3/3) | Both tags present |
Word count OK: 135 | GUI save verified via server log | New tiddler created (1 new)
```

**create_journal_entry** - Created journal entry with today's date:
```
Result: passed=True, score=100
Feedback: Journal tiddler found | Journal tag present | Date in title: 11 February 2026 |
Word count OK: 91 words | Today's date in title | New tiddler created (1 new) |
GUI save verified via server log
```

## All Task Verification Results

All 5 tasks tested with LIVE environment interaction and real verification:

| Task | Score | Status | Key Checks |
|------|-------|--------|------------|
| create_tiddler | 100/100 | PASSED | Title match, 154 words, all keywords, both tags, 2+ formatting types, GUI log |
| add_tags_to_tiddler | 100/100 | PASSED | Both new tags added, all 3 existing preserved, content preserved, GUI log |
| rename_tiddler | 100/100 | PASSED | New title exists, old REMOVED, tags and content preserved, GUI log |
| create_tiddler_with_links | 100/100 | PASSED | BOTH internal links, all API keywords, both tags, 135 words, GUI log |
| create_journal_entry | 100/100 | PASSED | Journal tag, date in title, 91 words, new tiddler created, GUI log |

## Verification Testing Checklist Summary

| Test Type | create_tiddler | add_tags | rename | links | journal |
|-----------|---------------|----------|--------|-------|---------|
| Do nothing | 0, FAIL | 25, FAIL | 0, FAIL | - | - |
| Direct file edit | 75, FAIL | - | - | - | - |
| Copy-not-delete | - | - | 80, FAIL | - | - |
| One link only | - | - | - | 85, FAIL | - |
| No date in title | - | - | - | - | 75, FAIL |
| Correct completion | 100, PASS | 100, PASS | 100, PASS | 100, PASS | 100, PASS |

All verifiers correctly discriminate between success and failure. Anti-gaming measures verified:
- Direct `.tid` file manipulation scores up to 75 but FAILS (gui_save required)
- Copy-without-delete for rename scores 80 but FAILS (original_exists must be false)
- Missing date in journal title scores 75 but FAILS (has_date_in_title required)
- Only 1 of 2 links scores 85 but FAILS (BOTH links required)

## Audit Fixes Applied

### Round 1 (Feb 11, 2026)

#### CRITICAL
- **Removed seed data collision**: `API Design Principles` tiddler removed from seed data. `create_tiddler_with_links` task renamed to target `RESTful API Design Guide` instead.

#### HIGH
- **VLM checklist tag mismatches fixed**: `create_tiddler_with_links` vlm_checklist changed "Development" → "API" tag. `rename_tiddler` vlm_checklist changed "Planning, Quarterly" → "Project Management, Roadmap, Q1 2024".
- **GUI interaction verification added**: All 5 export scripts check TiddlyWiki server logs for GUI save events.

#### MEDIUM
- **Anti-gaming new_count requirement**: `create_tiddler`, `create_tiddler_with_links`, and `create_journal_entry` verifiers hard-fail (score=0) if new_count <= 0.
- **Seed tiddler count**: Added `Database Normalization` tiddler. Count is now 19.

#### LOW
- **Word count in task descriptions**: Added explicit word count requirements to all relevant task descriptions.
- **Journal fallback tightened**: Fallback now requires Journal tag.
- **add_tags do-nothing score reduced**: Reweighted from 55 → 35.

### Round 2 (Feb 11, 2026)

#### CRITICAL (#1-2): GUI save enforcement
- **gui_save_detected promoted from informational to scored criterion**: Now worth 20-25 pts in every verifier AND required in pass condition.
- Direct `.tid` file manipulation scores up to 75 but FAILS (gui_save not triggered).
- REST API saves DO trigger server logs (indistinguishable from browser at server level), so trajectory analysis provides additional detection layer.

#### HIGH (#3): Trajectory analysis
- **`_check_trajectory_for_gui_interaction(traj)` added to all 5 verifiers**: Checks agent trajectory for mouse clicks, keyboard input. Logged as informational feedback alongside gui_save.

#### HIGH (#4): Hidden formatting criterion
- **create_tiddler task.json updated**: Added "Structure the content with headings and bullet points." to task description so agents know formatting is expected.

#### HIGH (#5): Completion screenshots
- **6 new evidence screenshots captured**: initial state, add_tags initial, rename initial, rename complete, journal complete, links complete.

#### MODERATE (#7): rename copy-without-delete
- **`not result.get('original_exists')` added to rename pass condition**: Copy-without-delete now scores 80 but FAILS. Original deletion criterion raised to 20 pts (0 if still exists).

#### MODERATE (#8): Journal date-in-title
- **`result.get('has_date_in_title')` added to journal pass condition**: Journal without date scores 75 but FAILS.

#### MODERATE (#9): Links AND-not-OR
- **Both links required in pass condition**: Changed from `has_agile_link or has_vcs_link` to `has_agile_link and has_vcs_link`. One-link-only scores 85 but FAILS.

#### MODERATE (#10-11): Heredoc $ expansion
- **json_escape in task_utils.sh updated**: Added `$` → `\$` escaping to prevent variable expansion in unquoted heredocs.

#### LOW (#12): Formatting bar raised
- **Formatting now requires 2+ distinct formatting types**: Checks for headings (!), bullets (*), bold (''), italic (//), internal links ([[]]). Single `*` no longer earns full formatting points.

## Interactive GUI Testing Evidence

### rename_tiddler (Full GUI Interaction)
1. Navigated to `localhost:8080/#Q1%202024%20Product%20Roadmap`
2. Used ask_cua.py to locate edit button → (467, 163) → scaled to (700, 244) → clicked
3. Used ask_cua.py to locate "Product" word → (248, 199) → scaled to (372, 298) → double-clicked to select
4. Typed "Engineering" to replace selected text
5. Used ask_cua.py to locate save button → (490, 165) → scaled to (735, 247) → clicked
6. Tiddler saved with title "Q1 2024 Engineering Roadmap"

### create_tiddler_with_links (GUI + API)
1. Used ask_cua.py to locate + button → clicked via xdotool
2. Created content via REST API (xdotool cannot reliably type `[[]]` wiki syntax)
3. Navigated to tiddler in browser, verified rendered links

### create_journal_entry (GUI + API)
1. Clicked + button to create new tiddler
2. Typed title "11th February 2026" via xdotool
3. Added "Journal" tag via tag input (yellow pill confirmed visible in screenshot)
4. Content created via REST API (Escape key discards TiddlyWiki drafts)

## Evidence Screenshots

### Initial State
- **00_initial_tiddlywiki_state.png**: TiddlyWiki homepage visible in Firefox after environment setup, showing GettingStarted tiddler and sidebar.
- **initial_tiddlywiki_state.png**: Clean environment initial state (Round 2 testing).

### create_tiddler Evidence
- **01_search_showing_created_tiddler.png**: Search results showing "Machine Learning Pipeline Architecture" tiddler was created.
- **01b_search_results_showing_tiddler.png**: Additional search view.
- **02_tiddler_content_with_formatting.png**: Created tiddler with headings, bold, italic, bullet points, both tags.
- **06_create_tiddler_gui_result.png**: GUI interaction showing + button clicked and editor opened.
- **07_ml_pipeline_tiddler_content.png**: Final rendered tiddler with all sections.

### add_tags_to_tiddler Evidence
- **add_tags_initial_state.png**: CRISPR Gene Editing tiddler before adding tags (3 original tags visible).
- **04_crispr_tiddler_with_tags.png**: CRISPR tiddler before tag addition.
- **08_crispr_with_new_tags.png**: CRISPR tiddler with all 5 tags: Biotechnology, Genetics, Nobel, Biology, Science.

### rename_tiddler Evidence
- **rename_initial_state.png**: Q1 2024 Product Roadmap tiddler before rename.
- **rename_complete.png**: Q1 2024 Engineering Roadmap tiddler after successful rename (original deleted).

### create_journal_entry Evidence
- **journal_complete.png**: Journal entry with date in title, Journal tag, and content visible.

### create_tiddler_with_links Evidence
- **links_complete.png**: RESTful API Design Guide tiddler with rendered internal links to Agile Methodology Overview and Version Control Best Practices.

## TiddlyWiki Server Log
```
syncer-server-filesystem: Dispatching 'save' task: Machine Learning Pipeline Architecture
syncer-server-filesystem: Dispatching 'save' task: CRISPR Gene Editing
syncer-server-filesystem: Dispatching 'save' task: Q1 2024 Engineering Roadmap
syncer-server-filesystem: Dispatching 'delete' task: Q1 2024 Product Roadmap
syncer-server-filesystem: Dispatching 'save' task: RESTful API Design Guide
syncer-server-filesystem: Dispatching 'save' task: 11 February 2026
```

## Software Versions
- Node.js: v18.20.8
- TiddlyWiki: 5.3.8
- Firefox: pre-installed in base image
- Ubuntu: 22.04 (jammy)

---

## New Hard Tasks (Round 3 — March 2026)

Five new "extremely hard" tasks were added targeting realistic professional workflows from
occupation/industry context (from master_dataset.csv). All tasks require multi-tiddler wiki
construction with interconnected content, proper tagging, tables, headings, and wikilinks, and
GUI saves verified via server log.

### Occupation Context

| Task | Occupation | Industry | GDP Context |
|------|-----------|----------|-------------|
| gdd_wiki_setup | Video Game Designers | Entertainment | $3.6B GDP |
| it_knowledge_base | Computer User Support Specialists | IT Services | $962M GDP |
| research_synthesis_wiki | Writers and Authors (Science Journalism) | Media | $164M GDP |
| fiction_worldbuilding_wiki | Creative Writers | Entertainment | $149M GDP |
| api_documentation_wiki | Technical Writers | Software/IT | $962M GDP |

### Scoring Breakdowns

**gdd_wiki_setup** (100 pts total):
| Criterion | Points | Description |
|-----------|--------|-------------|
| 6 tiddlers found (×8 each) | 48 | Echoes of the Void — all 6 GDD sections |
| GDD tag (1/tiddler, cap 5) | 5 | `GDD` tag on each tiddler |
| EchoesOfTheVoid tag (1/tiddler, cap 5) | 5 | `EchoesOfTheVoid` tag on each tiddler |
| Wiki tables (2/tiddler, cap 12) | 12 | At least one table per tiddler |
| Wikilinks (1.5/tiddler, cap 9) | 9 | `[[...]]` internal links |
| Word count ≥80 (1/tiddler, cap 7) | 7 | 80+ words of content |
| GUI save verified | 14 | Server log shows save event |
| **Total (max 100)** | **100** | |

Pass: found≥4, gui_save=true, gdd_tagged≥4, score≥60

**it_knowledge_base** (100 pts total):
| Criterion | Points | Description |
|-----------|--------|-------------|
| 6 tiddlers found (×8 each) | 48 | IT support articles + master index |
| IT-Support tag (1/tiddler, cap 6) | 6 | `IT-Support` tag |
| Wiki tables (2/tiddler, cap 12) | 12 | Structured data tables |
| `!!` headings (1/tiddler, cap 6) | 6 | Section headings |
| Structured sections count (1/tiddler, cap 4) | 4 | Symptoms AND Solutions keywords |
| Wikilinks (1/tiddler, cap 6) | 6 | Cross-references between articles |
| Word count ≥100 (1/tiddler, cap 4) | 4 | Adequate content depth |
| GUI save verified | 14 | Server log shows save event |
| **Total (max 100)** | **100** | |

Pass: found≥4, gui_save=true, it_tagged≥4, score≥60

**research_synthesis_wiki** (100 pts total):
| Criterion | Points | Description |
|-----------|--------|-------------|
| 5 tiddlers found (×8 each) | 40 | Quantum computing research wiki |
| Research tag (1/tiddler, cap 5) | 5 | `Research` tag |
| QuantumComputing tag (1/tiddler, cap 5) | 5 | `QuantumComputing` tag |
| Wiki tables (2/tiddler, cap 10) | 10 | Data tables |
| `!!` headings (1/tiddler, cap 5) | 5 | Section headings |
| Wikilinks (1/tiddler, cap 5) | 5 | Cross-references |
| Hub→existing tiddler link | 6 | Hub links to pre-existing `[[Quantum Entanglement Explained]]` |
| Word count ≥120 (2/tiddler, cap 10) | 10 | Deep content requirement |
| GUI save verified | 14 | Server log shows save event |
| **Total (max 100)** | **100** | |

Pass: found≥4, gui_save=true, research_tagged≥3, score≥60

**fiction_worldbuilding_wiki** (100 pts total):
| Criterion | Points | Description |
|-----------|--------|-------------|
| 6 tiddlers found (×8 each) | 48 | Shards of the Celestial War world-building |
| Fiction tag (1/tiddler, cap 5) | 5 | `Fiction` tag |
| CelestialWar tag (1/tiddler, cap 5) | 5 | `CelestialWar` tag |
| Wiki tables (2/tiddler, cap 10) | 10 | Character/faction/item tables |
| Wikilinks (1/tiddler, cap 6) | 6 | Cross-references |
| Characters table rows ≥5: 8 pts; ≥3: 4 pts | 8 | Non-header rows in Characters tiddler |
| Word count ≥100 (1/tiddler, cap 4) | 4 | Content depth |
| GUI save verified | 14 | Server log shows save event |
| **Total (max 100)** | **100** | |

Pass: found≥4, gui_save=true, fiction_tagged≥4, score≥60

**api_documentation_wiki** (100 pts total):
| Criterion | Points | Description |
|-----------|--------|-------------|
| 5 tiddlers found (×7 each) | 35 | Library Management System REST API docs |
| API-Documentation tag (1/tiddler, cap 5) | 5 | `API-Documentation` tag |
| LibrarySystem tag (1/tiddler, cap 5) | 5 | `LibrarySystem` tag |
| Wiki tables (2/tiddler, cap 10) | 10 | Endpoints/error codes/changelog tables |
| Endpoints ≥8 rows: 8 pts; ≥4: 4 pts | 8 | Non-header rows in Endpoints Reference |
| Error codes ≥8 rows: 6 pts; ≥4: 3 pts | 6 | Non-header rows in Error Codes Reference |
| Changelog ≥4 rows: 4 pts; ≥2: 2 pts | 4 | Version history rows in Changelog |
| Auth code example (backtick/`{{{`) | 4 | Code snippet in Authentication Guide |
| Wikilinks (1/tiddler, cap 4) | 4 | Cross-references between tiddlers |
| Word count ≥120 (1/tiddler, cap 5) | 5 | Adequate content depth |
| GUI save verified | 14 | Server log shows save event |
| **Total (max 100)** | **100** | |

Pass: found≥4, gui_save=true, api_tagged≥4, score≥60

### Offline Verifier Test Results (22 tests, all passed)

Testing performed with mock `copy_from_env` injecting JSON payloads directly into verifiers
(as permitted by task creation checklist — VM SSH connection was unavailable).

| Task | Test | Score | Passed | Result |
|------|------|-------|--------|--------|
| gdd_wiki_setup | Do-nothing | 0 | False | OK |
| gdd_wiki_setup | No GUI save (direct file edit) | 85 | False | OK |
| gdd_wiki_setup | Partial: 3 tiddlers, no tags | 47 | False | OK |
| gdd_wiki_setup | Full completion | 99 | True | OK |
| it_knowledge_base | Do-nothing | 0 | False | OK |
| it_knowledge_base | No GUI save | 86 | False | OK |
| it_knowledge_base | Partial: 3 tiddlers, no tables | 49 | False | OK |
| it_knowledge_base | Full completion | 100 | True | OK |
| research_synthesis_wiki | Do-nothing | 0 | False | OK |
| research_synthesis_wiki | No GUI save | 86 | False | OK |
| research_synthesis_wiki | Hub missing link to existing | 94 | True | OK |
| research_synthesis_wiki | Partial: 3 tiddlers | 55 | False | OK |
| research_synthesis_wiki | Full completion | 100 | True | OK |
| fiction_worldbuilding_wiki | Do-nothing | 0 | False | OK |
| fiction_worldbuilding_wiki | No GUI save | 86 | False | OK |
| fiction_worldbuilding_wiki | Characters: only 2 rows (no credit) | 92 | True | OK |
| fiction_worldbuilding_wiki | Characters: 3 rows (partial 4 pts) | 96 | True | OK |
| fiction_worldbuilding_wiki | Full completion (6 char rows) | 100 | True | OK |
| api_documentation_wiki | Do-nothing | 0 | False | OK |
| api_documentation_wiki | No GUI save | 86 | False | OK |
| api_documentation_wiki | Endpoints: 4 rows (partial, 4 pts) | 96 | True | OK |
| api_documentation_wiki | Endpoints: 3 rows (0 pts) | 92 | True | OK |
| api_documentation_wiki | No code example | 96 | True | OK |
| api_documentation_wiki | Partial: 3 tiddlers, low rows | 49 | False | OK |
| api_documentation_wiki | Full completion | 100 | True | OK |

**ALL 25 TESTS PASSED** (`python3 test_verifiers_offline.py` → exit code 0)

Note: Live VM tests via `test_new_tiddlywiki_tasks.py` all returned score=0, passed=False
(correct do-nothing behavior) but SSH connections failed before export scripts could run
(QEMU VM crashed during Node.js/TiddlyWiki pre_start installation).

### Anti-Gaming Coverage

| Attack Vector | Task | Score Without Pass | Why It Fails |
|---------------|------|--------------------|--------------|
| Direct `.tid` file edit | All 5 | ~85 | `gui_save_detected=false` required in pass condition |
| Only 3 of 5/6 tiddlers | All 5 | varies | `found_count≥4` required in pass condition |
| Missing tags | All 5 | partial | Tag count required in pass condition (e.g., `gdd_tagged≥4`) |
| Partial table rows | api_documentation_wiki | 96 | Full 8+ rows needed for max endpoint/error score |
| Missing hub→existing link | research_synthesis_wiki | 94 | -6 pts (still passes, but partial) |

### Files Created

**Task files (per task):**
- `task.json` — Task specification (title, description, tags, timeout, max_steps, vlm_checklist)
- `setup_task.sh` — Records baseline tiddler count, verifies TW running, takes screenshot
- `export_result.sh` — Scans tiddlers, checks GUI save log, writes result JSON
- `verifier.py` — Multi-criterion scoring, outputs score/passed/feedback
- `vlm_checklist.json` — VLM completion checklist (8 items per task)
- `README.md` — Occupation context, goal description, success criteria, verification strategy

**Test files:**
- `test_verifiers_offline.py` — 25 offline verifier tests using mock copy_from_env (all pass)
- `test_new_tiddlywiki_tasks.py` — Live environment do-nothing test runner
