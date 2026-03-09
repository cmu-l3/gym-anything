# Task: Setup Competency Framework

## Overview

Configure a complete competency-based learning system for the PSY301 Educational Psychology course. This reflects real instructional design work: an instructional designer must create a competency framework in the site administration area, populate it with domain-specific competencies, enable competency tracking in the target course, and then link individual competencies to specific course activities. The task spans multiple disconnected parts of the Moodle interface, making it considerably more difficult than single-screen tasks.

## Occupation

**Instructional Designer / E-learning Specialist**

Instructional designers at higher education institutions are responsible for aligning curriculum with accreditation standards and learning outcome frameworks. A core part of this role involves configuring LMS competency systems so that student achievement of measurable outcomes can be tracked and reported to accrediting bodies.

## Target State

- **Course**: Educational Psychology (PSY301), Humanities category
- **Framework**: "Educational Psychology Competencies" (shortname: `edu-psych-comp`) created in Site Administration > Competencies
- **Competencies in framework** (exactly 3):
  - Learning Theories and Applications
  - Developmental Psychology
  - Educational Assessment and Measurement
- **Course competency tracking**: enabled in PSY301 course settings (competencies linked to course)
- **Activity-competency links**:
  - "Learning Theories Essay" assignment linked to "Learning Theories and Applications"
  - "Assessment Design Project" assignment linked to "Educational Assessment and Measurement"
- **Login**: admin / Admin1234!
- **Application URL**: http://localhost/moodle

## Step-by-Step Task Description

1. Log in to Moodle as admin (admin / Admin1234!)
2. Navigate to Site Administration > Competencies > Competency frameworks
3. Create a new framework:
   - Full name: "Educational Psychology Competencies"
   - Short name: "edu-psych-comp"
   - Save the framework
4. Inside the framework, add three competencies:
   - "Learning Theories and Applications"
   - "Developmental Psychology"
   - "Educational Assessment and Measurement"
5. Navigate to the PSY301 course
6. Open Course Settings (gear icon > Edit settings) and ensure competencies are enabled, then go to the Competencies tab in course settings and add competencies to the course (or use the dedicated Competencies page in the course navigation)
7. Link the "Learning Theories and Applications" competency to the "Learning Theories Essay" assignment activity in PSY301
8. Link the "Educational Assessment and Measurement" competency to the "Assessment Design Project" assignment activity in PSY301

## Why This Task is Hard (very_hard)

- **Multi-location navigation**: The agent must visit at least three distinct parts of Moodle: site administration (framework creation), course settings (enable competencies), and individual activity settings (link competencies). These are not linked by obvious breadcrumbs.
- **Obscure admin path**: The Competencies section is buried under Site Administration and is rarely used. Agents unfamiliar with Moodle's information architecture will struggle to find it.
- **Two-phase linking**: Competencies must first be linked at the course level before they can appear as options when linking to individual activities. Missing this step causes the activity-linking step to fail silently.
- **Exact naming required**: The framework shortname `edu-psych-comp` and competency names must match exactly for the verifier to succeed.
- **No visual confirmation**: Moodle does not provide a summary view that shows all competency links at once; the agent must check each activity individually to confirm links.

## Success Criteria (100 points)

| Criterion | Points | Verification |
|-----------|--------|-------------|
| Competency framework "edu-psych-comp" exists | 20 | `mdl_competency_framework` WHERE shortname LIKE `%edu%psych%` |
| All 3 required competencies present in framework | 25 | 8 pts each: `mdl_competency` WHERE shortname LIKE pattern per competency |
| PSY301 has at least 1 course-competency link | 20 | `mdl_competency_coursecomp` WHERE courseid = PSY301 id |
| "Learning Theories Essay" activity has competency linked | 15 | `mdl_competency_modulecomp` WHERE cmid = essay cmid |
| "Assessment Design Project" activity has competency linked | 20 | `mdl_competency_modulecomp` WHERE cmid = project cmid |

Pass threshold: 60 points

## Verification Strategy

- **Framework check**: Query `mdl_competency_framework` by shortname pattern `%edu%psych%` or exact `edu-psych-comp`
- **Competency check**: Query `mdl_competency` filtered by `competencyframeworkid` and shortname LIKE patterns for each of the 3 required competencies
- **Course link check**: Count rows in `mdl_competency_coursecomp` for PSY301's course ID
- **Activity link check**: Resolve each assignment's course module ID via JOIN of `mdl_course_modules`, `mdl_assign`, `mdl_modules`; then count rows in `mdl_competency_modulecomp` for those cmids
- **Partial credit**: Each of the 3 competencies scores 8 points independently (max 24, capped at 25 when all present); activity links scored independently

## Database Schema

- `mdl_competency_framework`: id, shortname, idnumber, description, timecreated, usermodified
- `mdl_competency`: id, competencyframeworkid, shortname, idnumber, description, parentid
- `mdl_competency_coursecomp`: id, courseid, competencyid, ruleoutcome, sortorder
- `mdl_competency_modulecomp`: id, cmid, competencyid, ruleoutcome
- `mdl_course_modules`: id, course, module, instance, section, visible
- `mdl_assign`: id, course, name, intro

## Pre-conditions (set up by setup_task.sh)

- PSY301 "Educational Psychology" course exists in Humanities (HUM) category
- Three assignments in PSY301: "Learning Theories Essay", "Child Development Case Study", "Assessment Design Project"
- `enablecompetencies = 1` set in Moodle site configuration
- No competency framework exists at task start (agent must create it)

## Edge Cases

- If the agent uses a slightly different framework shortname (e.g., `edu_psych_comp`), the verifier uses a LIKE pattern `%edu%psych%` to allow minor variations
- If the agent links competencies to the course but not to individual activities, partial credit is awarded (up to 40 points for framework + competencies + course link)
- Competency names are matched case-insensitively via LIKE patterns: `%learning%theor%`, `%develop%`, `%assessment%`
- The "Child Development Case Study" assignment intentionally does NOT need a competency linked (only 2 of 3 assignments require links)
