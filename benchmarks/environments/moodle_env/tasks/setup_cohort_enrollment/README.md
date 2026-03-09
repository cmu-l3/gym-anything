# Task: Setup Cohort Enrollment

## Overview

Configure site-wide cohort enrollment for a new Engineering department cohort so that
five newly created students are automatically enrolled in two required Engineering courses
via Moodle's cohort synchronization plugin. This task reflects a real LMS administrator
workflow: bulk-enroll a cohort of students without touching each course enrollment roster
individually, leveraging Moodle's cohort sync feature for scalable, automated enrollment.

## Occupation

**LMS Administrator / Student Information System Coordinator**

LMS administrators at universities are responsible for synchronizing enrollment data between
the student information system and the LMS. Cohort-based enrollment is the recommended
Moodle pattern for managing groups of students who share a common curriculum — the
administrator creates a site-wide cohort, assigns students to it, then configures each
course to automatically sync enrollment from that cohort. Any future student added to the
cohort is instantly enrolled in all linked courses.

## Target State

- **Cohort**: "Engineering Program Cohort 2024" (idnumber: `eng2024`) created as a site-wide cohort
- **Cohort members** (exactly 5): eng_alice, eng_bob, eng_carol, eng_dave, eng_emma
- **CS110** (Computer Science Fundamentals): cohort sync enrollment configured for "Engineering Program Cohort 2024"; all 5 members enrolled as students
- **ENG110** (Introduction to Engineering): cohort sync enrollment configured for "Engineering Program Cohort 2024"; all 5 members enrolled as students
- **Login**: admin / Admin1234!
- **Application URL**: http://localhost/moodle

## Step-by-Step Task Description

1. Log in to Moodle as admin (admin / Admin1234!)
2. Navigate to **Site administration > Users > Cohorts**
3. Click "Add new cohort":
   - Name: "Engineering Program Cohort 2024"
   - Cohort ID: `eng2024`
   - Context: System (site-wide)
   - Save the cohort
4. Open the cohort and add all 5 students as members:
   - eng_alice (Alice Chen)
   - eng_bob (Bob Martinez)
   - eng_carol (Carol Kim)
   - eng_dave (Dave Patel)
   - eng_emma (Emma Johnson)
5. Navigate to the **CS110** course (Computer Science Fundamentals)
6. Go to **Participants > Enrollment methods**
7. From the "Add method" dropdown, choose **Cohort sync**:
   - Cohort: "Engineering Program Cohort 2024"
   - Assign role: Student
   - Save
8. Navigate to the **ENG110** course (Introduction to Engineering)
9. Go to **Participants > Enrollment methods**
10. From the "Add method" dropdown, choose **Cohort sync**:
    - Cohort: "Engineering Program Cohort 2024"
    - Assign role: Student
    - Save
11. Confirm that all 5 students now appear in the participants list of both CS110 and ENG110

## Why This Task is Hard (very_hard)

- **Cross-context navigation**: The agent must move between two completely separate areas
  of Moodle — site administration (cohort management) and course administration (enrollment
  methods). These areas have different navigation menus with no direct links between them.
- **Site-admin-only feature**: Cohorts are not a course-level feature. The agent must know
  to navigate to Site administration, not the course settings, to create the cohort. Many
  agents look for cohort management inside the course and fail to find it.
- **Enrollment methods vs. manual enrollment**: Adding a cohort sync enrollment requires
  going to the "Enrollment methods" page (not just Participants), choosing the correct
  plugin from a dropdown (Cohort sync), and then selecting the specific cohort. This is
  a different workflow from manually enrolling individual users.
- **Two courses require separate configuration**: The agent must repeat the enrollment-method
  configuration for both CS110 and ENG110 without being reminded, requiring attention to
  the multi-course requirement.
- **Verification requires understanding sync**: Cohort sync enrollment triggers automatic
  enrollment of all current cohort members. The agent should understand that adding the
  enrollment method is sufficient — individual enrollment records are created automatically
  by the sync plugin — but must confirm this actually occurred.
- **Order dependency**: Cohort must be created and populated before enrollment methods are
  configured; otherwise the cohort may not appear in the dropdown or the sync may not
  process the members.

## Success Criteria (100 points)

| Criterion | Points | Verification |
|-----------|--------|-------------|
| Cohort "eng2024" (or "Engineering Program Cohort 2024") exists | 15 | `mdl_cohort` WHERE idnumber='eng2024' OR name LIKE '%engineering%cohort%2024%' |
| All 5 required students in cohort | 25 | 5 pts each: `mdl_cohort_members` JOIN `mdl_user` per username |
| Cohort sync enrollment configured for CS110 | 20 | `mdl_enrol` WHERE enrol='cohort' AND courseid=CS110_id AND customint1=cohort_id |
| Cohort sync enrollment configured for ENG110 | 20 | `mdl_enrol` WHERE enrol='cohort' AND courseid=ENG110_id AND customint1=cohort_id |
| All 5 cohort members enrolled in CS110 | 10 | `mdl_user_enrolments` JOIN `mdl_enrol` for CS110; 5 pts if >= 3 enrolled |
| All 5 cohort members enrolled in ENG110 | 10 | `mdl_user_enrolments` JOIN `mdl_enrol` for ENG110; 5 pts if >= 3 enrolled |

Pass threshold: 60 points

## Verification Strategy

- **Cohort check**: Query `mdl_cohort` by idnumber `eng2024` or name pattern `%engineering%cohort%2024%`
- **Member check**: For each of the 5 usernames, confirm a row exists in `mdl_cohort_members` joined to `mdl_user`
- **Enrollment method check**: Confirm a row in `mdl_enrol` with `enrol='cohort'`, matching `courseid` and `customint1` equal to the cohort ID
- **Enrollment count check**: Count distinct active `user_enrolments` rows for the 5 cohort users in each course
- **Partial credit**: 5 points per cohort member found (criterion 2); 5 points for >= 3 enrolled out of 5 (criteria 5 & 6)

## Database Schema

- `mdl_cohort`: id, name, idnumber, contextid, description
- `mdl_cohort_members`: cohortid, userid, timeadded
- `mdl_enrol`: id, enrol, courseid, customint1 (cohort id for cohort sync), status, roleid
- `mdl_user_enrolments`: id, enrolid, userid, status (0=active)
- `mdl_user`: id, username, firstname, lastname

## Pre-conditions (set up by setup_task.sh)

- Five new student users created: eng_alice (Alice Chen), eng_bob (Bob Martinez), eng_carol
  (Carol Kim), eng_dave (Dave Patel), eng_emma (Emma Johnson)
- Course ENG110 "Introduction to Engineering" created in Engineering (ENG) category
- CS110 "Computer Science Fundamentals" already exists in Engineering (ENG) category
- No cohorts exist at task start (agent must create "Engineering Program Cohort 2024")
- Cohort enrollment plugin enabled (available by default in Moodle 4.5)

## Edge Cases

- If the agent uses a slightly different cohort name (e.g., omitting "Program"), the
  verifier uses a LIKE pattern `%engineering%cohort%2024%` for matching; however, the
  idnumber `eng2024` is checked exactly
- Cohort sync enrollment automatically enrolls existing cohort members; the agent does
  not need to manually enroll each user after adding the enrollment method
- The verifier checks enrollments via `mdl_user_enrolments` regardless of whether they
  were created by cohort sync or manually, to allow for manual-enrollment fallback
- If the cohort is created but the enrollment method is not configured, members will be
  in the cohort but NOT enrolled in the courses (criteria 3/4 fail; 5/6 may fail)
