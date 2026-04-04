# Task: Cloud Migration Deck Repair

## Overview

**Occupation**: Computer Systems Analysts / IT Managers
**Difficulty**: very_hard
**Domain**: Enterprise IT / Cloud Infrastructure

## Background

Computer Systems Analysts routinely review technical presentations before they reach senior leadership. A junior analyst prepared a cloud migration status deck but introduced several errors. The analyst is asked to find and fix all issues before the CTO review.

This task tests: (1) finding and fixing a spelling error without being told which slide, (2) identifying and completing an empty slide that requires domain knowledge, (3) adding professional speaker notes throughout, and (4) applying consistent presentation polish (transitions).

## Starting State

A 9-slide ODP presentation at `/home/ga/Documents/Presentations/cloud_migration_deck.odp` with the following defects:

1. **Slide 3 title**: Contains the typo "Infrastrucutre" (should be "Infrastructure")
2. **Slide 6 (Security Overview)**: Body is completely empty — no content whatsoever
3. **All slides**: No speaker notes
4. **All slides**: No slide transitions applied

## Goal / End State

The repaired deck saved at `/home/ga/Documents/Presentations/cloud_migration_deck.odp` must:
1. Have the typo corrected in all occurrences
2. Have the Security Overview slide populated with at least 3 substantive security controls/measures
3. Have speaker notes on at least 5 of the 9 slides
4. Have slide transitions applied consistently on at least 7 slides

The task description does NOT specify which menus to use or the exact UI path — the agent must discover the errors and determine how to fix them.

## Success Criteria

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Typo "Infrastrucutre" absent from all slides | 25 | Required |
| Security Overview slide has >= 3 content lines | 25 | Required |
| Speaker notes on >= 5 slides | 30 | Required |
| Transitions on >= 7 slides | 20 | Required |
| **Pass threshold** | **65** | — |

## Verification Strategy

1. **ODP existence**: Fail immediately if file missing or unreadable
2. **Typo check**: Case-insensitive search for "infrastrucutre" in all text extracted from content.xml
3. **Security slide**: Find the slide with "security overview" in title; count non-empty content lines >10 chars
4. **Notes**: Count `<presentation:notes>` elements with >20 non-tag characters
5. **Transitions**: Count slides with `presentation:transition-style=` attribute or `<presentation:transition>` child element

## Edge Cases

- If the agent deletes slide 6 entirely, security check will fail
- If agent renames the Security slide significantly, detection may fail
- Transition detection requires LibreOffice's native ODP transition format
