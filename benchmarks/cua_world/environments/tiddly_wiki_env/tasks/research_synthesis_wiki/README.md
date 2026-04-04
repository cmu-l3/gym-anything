# research_synthesis_wiki

## Overview

**Occupation**: Writers and Authors (Science Journalism)
**Difficulty**: hard
**Domain**: Research Note Organization

A science journalist organizing research notes for an article on quantum computing. This reflects how science writers use note-taking tools to synthesize research from multiple sources into a coherent article structure. The wiki already contains a pre-existing "Quantum Entanglement Explained" tiddler that the hub must link to.

## Goal

Create 5 interconnected tiddlers forming a research synthesis wiki:

1. **Quantum Computing - Research Hub** — 200+ word synthesis overview; table of subtopics; links to all 4 new tiddlers AND to the existing `[[Quantum Entanglement Explained]]` tiddler
2. **Quantum Computing - Key Concepts** — Foundational concepts table (qubits, superposition, interference, gates, decoherence): Concept | Definition | Why It Matters | Classical Analogue
3. **Quantum Computing - Current Hardware** — Survey of 2024 hardware approaches; table: Approach | Companies | Qubit Count | Advantage | Challenge
4. **Quantum Computing - Real-World Applications** — Industry applications; table: Industry | Application | Quantum Advantage | Timeline
5. **Quantum Computing - Challenges and Roadmap** — Technical barriers; table: Challenge | Status | Proposed Solutions | Expected Resolution

All 5 tiddlers must be tagged `Research` and `QuantumComputing`, contain `!!` headings, tables, and wikilinks.

## Success Criteria

- All 5 tiddlers exist by exact title
- Each has `Research` and `QuantumComputing` tags
- Hub tiddler links to pre-existing `Quantum Entanglement Explained`
- Each contains at least one wiki table
- Each has at least 120 words
- GUI saves confirmed in server log
- Score ≥ 60, found_count ≥ 4, research_tagged ≥ 3, gui_save = true

## Pre-existing Tiddler Dependency

The seed data includes "Quantum Entanglement Explained" as one of the 19 seeded tiddlers. The hub tiddler must include `[[Quantum Entanglement Explained]]` or otherwise reference this tiddler title.

The export script checks for the pre-existing tiddler link by searching the Hub tiddler text for "quantum entanglement explained" (case-insensitive).

## Verification Strategy

**Export script** (`export_result.sh`): Python inline script finds each tiddler, extracts tags, checks for headings/tables/links/word count. For the Hub tiddler, checks if "Quantum Entanglement Explained" appears in the text (either as wikilink or plain text reference).

**Verifier** (`verifier.py`): Multi-criterion scoring:
| Criterion | Points |
|-----------|--------|
| Each tiddler found (×5) | 8 pts each = 40 |
| Research tag (1/tiddler, cap 5) | 5 |
| QuantumComputing tag (1/tiddler, cap 5) | 5 |
| Tables (2/tiddler, cap 10) | 10 |
| Section headings (1/tiddler, cap 5) | 5 |
| Wikilinks (1/tiddler, cap 5) | 5 |
| Hub → existing tiddler link | 6 |
| Word count ≥120 (2/tiddler, cap 10) | 10 |
| GUI save | 14 |
| **Total** | **100** |

## Tag Normalization

`QuantumComputing` tag: verifier normalizes tags by removing spaces and hyphens before checking. So `Quantum Computing`, `quantum-computing`, or `QuantumComputing` all match.

## Anti-Gaming

Requires `gui_save_detected = true` to pass. Server log checked for: "Quantum", "Research Hub", "Key Concepts", "Hardware", "Application", "Challenge".
