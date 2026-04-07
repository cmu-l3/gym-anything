# Task: Create Competency Framework and Link to Course (`create_competency_framework@1`)

## Overview
Create a competency framework for digital literacy skills, populate it with three defined competencies, and link those competencies to the Introduction to Computer Science (CS101) course. This tests the agent's ability to navigate Moodle's competency-based education features, a multi-step administrative workflow involving framework creation, competency definition, and course-level competency linking.

## Rationale
**Why this task is valuable:**
- Tests navigation of Moodle's competency management system
- Involves a multi-step workflow across different admin interfaces (site admin → framework → competencies → course settings)
- Requires understanding of hierarchical data relationships
- Verifiable through multiple independent database tables

**Real-world Context:** An instructional coordinator is rolling out competency-based education. They need to define a "Digital Literacy" framework and link its competencies to the CS101 course so instructors can rate student mastery.

## Task Description
**Goal:** Create a "Digital Literacy Framework" with three specific competencies and link them to the CS101 course.

**Starting State:** Moodle is running. Competencies are enabled at the site level. The CS101 course exists. A "Digital Literacy Scale" is available for use.

**Expected Actions:**
1. Log in to Moodle as admin.
2. Navigate to **Site administration > Competencies > Competency frameworks**.
3. Create a new framework:
   - Name: **Digital Literacy Framework**
   - ID number: **DLF001**
   - Scale: **Digital Literacy Scale**
4. Add three competencies to the framework:
   - **Information Literacy** (ID: `DL-IL`)
   - **Digital Communication** (ID: `DL-DC`)
   - **Data Analysis Basics** (ID: `DL-DA`)
5. Navigate to course **Introduction to Computer Science (CS101)**.
6. Go to **Competencies** in the course menu.
7. Link all three new competencies to the course.

## Verification Strategy
- **Framework Check**: Verify `mdl_competency_framework` contains `DLF001`.
- **Competency Check**: Verify `mdl_competency` contains the 3 ID numbers linked to the framework.
- **Link Check**: Verify `mdl_competency_coursecomp` links these competencies to the CS101 course ID.
- **Anti-Gaming**: Ensure records were created after task start time.

## Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Framework Created | 15 | Framework exists with ID 'DLF001' |
| Framework Name | 10 | Name contains 'Digital Literacy' |
| Competencies Created | 30 | 3 specific competencies exist (10 pts each) |
| Competencies Linked | 30 | 3 competencies linked to CS101 (10 pts each) |
| Scale Configured | 15 | Correct scale selected and configured |
| **Total** | **100** | |

Pass Threshold: 55 points (Must have framework + at least 2 competencies created)