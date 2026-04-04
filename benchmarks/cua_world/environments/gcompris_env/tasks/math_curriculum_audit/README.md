# Math Curriculum Audit

## Task Overview

**Occupation**: Curriculum Coordinator (Elementary School District)
**Difficulty**: Hard
**Timeout**: 600 seconds / 70 max steps

## Domain Context

Curriculum coordinators in elementary school districts regularly audit educational software to determine alignment with state and national mathematics standards (e.g., Common Core State Standards). A formal audit of GCompris's math offerings requires systematically cataloging every activity across all sub-categories, personally interacting with key activities to assess instructional quality, and producing a structured report for district leadership review.

## Goal

Produce a formal **Mathematics Curriculum Audit Report** at `~/Desktop/math_curriculum_audit.txt` after:
1. Exploring all three Math sub-tabs: **Numeration**, **Arithmetic**, **Measures**
2. Interacting with at least one activity from Numeration and one from Arithmetic
3. Listing every activity name visible in each sub-tab

## Success Criteria

The report file `~/Desktop/math_curriculum_audit.txt` must:
- Be created after the task started
- Be at least 400 bytes in size
- Contain labeled sections for **Numeration**, **Arithmetic**, and **Measures**
- Mention specific GCompris activity names from the math section (e.g., additions, subtraction, numbers, counting, weights)

## Scoring (100 points)

| Criterion | Points |
|-----------|--------|
| Report file exists | 10 |
| Report created after task started (gate) | 15 |
| Report is ≥400 bytes | 10 |
| Numeration section present | 20 |
| Arithmetic section present | 20 |
| Measures section present | 10 |
| 3+ specific math activity keywords | 15 |

Pass threshold: **60 points**

## Verification Strategy

`export_result.sh` checks:
- File existence and modification time at `/home/ga/Desktop/math_curriculum_audit.txt`
- File size
- Grep for section keywords: "numeration", "arithmetic", "measures"
- Grep for activity name keywords: "addition", "subtraction", "count", "number", "algebra", "weight", "ruler"

`verifier.py` applies weighted scoring with a mandatory timestamp gate.

## GCompris Math Activities (Reference)

**Numeration tab**: Activities about recognizing and ordering numbers, counting objects, number sequences
**Arithmetic tab**: Learn additions, Learn subtractions, Learn multiplications, Algebra
**Measures tab**: Activities about comparing weights, measuring with ruler, time measurement

## Notes

- The Math section is accessed via the sheep/numbers icon in GCompris's top category bar
- Each sub-category has its own tab within the Math section
- Activities are arranged in a grid; scrolling may reveal additional activities
