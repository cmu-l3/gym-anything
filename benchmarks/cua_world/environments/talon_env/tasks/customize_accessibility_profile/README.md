# Task: customize_accessibility_profile

## Overview

**Difficulty**: very_hard
**Domain**: Assistive Technology / Healthcare
**Occupation Context**: Assistive technology (AT) specialists who configure Talon Voice for healthcare professionals who rely on voice control for computer access due to motor disabilities. Healthcare environments require both standardized radio communication vocabulary (NATO alphabet, well-known to clinical staff) and domain-specific medical abbreviations.

## Scenario

An AT specialist is configuring Talon Voice for a clinical nurse specialist who has wrist tendinopathy and cannot use a keyboard. The nurse works across multiple hospital systems and communicates using NATO phonetic conventions (common in clinical radio and emergency settings). The nurse also dictates medical abbreviations constantly and needs them available as quick voice aliases.

Two configuration tasks are required:

1. **Update the phonetic alphabet** (`letter.talon-list`) from the community's default non-standard phonetics (air, bat, cap...) to the full 26-letter NATO standard (alpha, bravo, charlie...).
2. **Create a medical vocabulary list** (`user.medical_terms.talon-list`) with at least 8 common medical abbreviations as voice command aliases.

## Goal

### Task A: Update Phonetic Alphabet
File: `C:\Users\Docker\AppData\Roaming\Talon\user\community\core\keys\letter.talon-list`

Replace all 26 phonetic letter words with NATO standard:
- alpha: a, bravo: b, charlie: c, delta: d, echo: e
- foxtrot: f, golf: g, hotel: h, india: i, juliett: j
- kilo: k, lima: l, mike: m, november: n, oscar: o
- papa: p, quebec: q, romeo: r, sierra: s, tango: t
- uniform: u, victor: v, whiskey: w, x-ray: x, yankee: y
- zulu: z

Keep the `list: user.letter` header and the `-` separator intact.

### Task B: Create Medical Vocabulary List
File: `C:\Users\Docker\AppData\Roaming\Talon\user\community\core\vocabulary\user.medical_terms.talon-list`

Create a new `.talon-list` file with:
- Header: `list: user.medical_terms`
- At least 8 medical abbreviation entries such as:
  - stat, prn, bid, tid, qid, npo, icu, ppe, ekg, mri, cpr, dnr

## Why This Is Hard (very_hard)

- Agent must know the `.talon-list` file format (`list: <name>` header + `-` separator + entries)
- Agent must look up all 26 official NATO phonetic words and their correct spelling
- "juliett" (with double-t) and "x-ray" (with hyphen) are common spelling mistakes
- Agent must navigate the community directory structure to find the correct file path
- Two separate files must be created/edited correctly
- No step-by-step guidance is given

## Verification Strategy

| Criterion | Weight | Check |
|-----------|--------|-------|
| `user.letter` header preserved in letter.talon-list | 10 pts | First non-comment line must be `list: user.letter` |
| All 26 NATO phonetics correct | Up to 50 pts | 2 pts per correct mapping (alpha→a, bravo→b, ...) |
| `user.medical_terms.talon-list` has correct header | 15 pts | `list: user.medical_terms` |
| Medical list has >= 8 terms | 25 pts | Count of key-value pairs in body |

Pass threshold: 60 points.

## Starting State

- `letter.talon-list` is reset to original non-NATO phonetics (air, bat, cap, drum, each...)
- `core/vocabulary/` directory exists but `user.medical_terms.talon-list` does NOT
- `letter.talon-list` is opened in the text editor at task start

## NATO Alphabet Reference

| NATO Word | Letter | | NATO Word | Letter |
|-----------|--------|--|-----------|--------|
| alpha | a | | november | n |
| bravo | b | | oscar | o |
| charlie | c | | papa | p |
| delta | d | | quebec | q |
| echo | e | | romeo | r |
| foxtrot | f | | sierra | s |
| golf | g | | tango | t |
| hotel | h | | uniform | u |
| india | i | | victor | v |
| juliett | j | | whiskey | w |
| kilo | k | | x-ray | x |
| lima | l | | yankee | y |
| mike | m | | zulu | z |
