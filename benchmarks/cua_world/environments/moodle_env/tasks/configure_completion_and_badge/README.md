# Task: configure_completion_and_badge

## Occupation

University Biology Instructor / LMS Course Administrator

The agent acts as the instructor for BIO302 Advanced Cell Biology at State University. The course already exists with five activities created, but no completion tracking has been configured. The instructor must establish a complete student progression tracking system so that students and instructors can monitor progress through the course and so that successful students automatically receive a digital credential.

## Task Overview

The agent must configure Moodle's activity completion, course completion, and badge systems for BIO302 Advanced Cell Biology. This involves three distinct phases of work in three separate areas of the Moodle interface:

1. Configure activity-level completion conditions for each of the five course activities.
2. Configure course-level completion criteria requiring all five activities to be completed.
3. Create a course badge with course completion as the award criterion and a 3-year expiry.

## Course

- **Short name**: BIO302
- **Full name**: Advanced Cell Biology
- **Category**: Science (SCI)

## Activities and Required Completion Settings

| Activity Name | Module Type | Required Completion Condition |
|---|---|---|
| Lab Safety and Ethics Module | Page (resource) | Student views the page |
| Cell Membrane Transport Lab | Assignment | Student submits the assignment |
| Molecular Biology Quiz | Quiz | Student achieves a passing grade (70% or higher) |
| Research Discussion Forum | Forum | Student makes at least one post |
| Final Research Report | Assignment | Student submits the assignment |

### Notes on Completion Configuration

- **View completion** (Page): In the activity completion settings, select "Students can manually mark this activity as done" or use automatic "Show activity as complete when conditions are met" with the "Require view" condition checked. In Moodle 4.x, this sets `completion=2` and `completionview=1` in `mdl_course_modules`.
- **Submit completion** (Assignments): Use automatic completion with "Student must submit this assignment" condition. This sets `completion=2` and `completionsubmit=1` on the assign record.
- **Pass grade completion** (Quiz): Use automatic completion with "Student must receive a grade" and "Student must receive a passing grade" conditions. The passing grade must be set to 70% in the quiz grade settings. This sets `completion=2`, `completionusegrade=1`, and `completionpassgrade=1` in `mdl_course_modules`.
- **Post completion** (Forum): Use automatic completion with "Student must create discussions or replies" condition set to at least 1 post. This sets `completion=2` and `completionposts=1` in the `mdl_forum` table.

## Course Completion Criteria

After configuring all five activities, the agent must navigate to the course completion settings page (Course administration > Course completion) and configure:

- **Condition type**: Activity completion
- **Required activities**: All five activities above must be checked
- **Aggregation**: All selected activities must be completed (AND logic)

This creates records in `mdl_course_completion_criteria` linking the course to each activity module.

## Badge Requirements

| Field | Value |
|---|---|
| Badge name | Advanced Cell Biology Scholar |
| Description | Awarded to students who successfully complete all BIO302 Advanced Cell Biology course requirements including laboratory work, assessments, and discussions. |
| Criteria | Course completion (student must complete BIO302) |
| Expiry type | Relative (expires after issue) |
| Expiry period | 3 years (approximately 94,608,000 seconds) |

The badge must be created within the BIO302 course (Badges section), not as a site-level badge. The badge criteria type for course completion is recorded as type 8 in `mdl_badge_criteria`.

## Why This Task Is Hard (Difficulty: very_hard)

This task is classified as very hard for several reasons:

1. **Five separate activity completion configurations**: Each activity must be individually edited. The agent must navigate to each activity's settings, locate the completion tracking section, select the correct condition type, and save. This is five sequential multi-step operations.

2. **Different completion conditions per activity type**: Each module type (page, assignment, quiz, forum) has different available completion options. The agent must know which option corresponds to the correct semantic (view vs. submit vs. pass grade vs. post).

3. **Quiz pass grade setup**: For the quiz, the agent must not only set completion to "pass grade required" but also ensure the quiz has a passing grade threshold configured (70%). This may require a separate step in the quiz grade settings.

4. **Course completion is a separate page**: After completing all five activity configurations, the agent must find and navigate to a different area of Moodle (Course administration > Course completion) to configure the course-level criteria.

5. **Badge creation spans multiple sub-steps**: Creating the badge requires navigating to Badges, creating the badge with metadata, uploading or selecting an image, saving, then navigating to Criteria, adding course completion as a criterion, saving, then navigating to Expiry to set the 3-year relative expiry.

6. **All work is in different Moodle interface sections**: Activity settings, course completion settings, and badge management are each in distinct parts of the Moodle navigation tree with no direct links between them.

## Verification Criteria

Scoring is out of 100 points. Pass threshold is 60 points.

| Criterion | Points | Condition |
|---|---|---|
| Lab Safety page: view completion | 15 | `completion=2` AND `completionview=1` in `mdl_course_modules` |
| Cell Membrane Transport Lab: submit completion | 15 | `completion=2` AND submit tracked (via `completionsubmit=1` on assign or `completionusegrade=1` on cm) |
| Molecular Biology Quiz: pass grade completion | 15 | `completion=2` AND `completionusegrade=1` AND `completionpassgrade=1` |
| Research Discussion Forum: post completion | 15 | `completion=2` AND `completionposts >= 1` in `mdl_forum` |
| Final Research Report: submit completion | 10 | `completion=2` AND submit tracked |
| Course completion criteria configured | 15 | At least 1 record in `mdl_course_completion_criteria` for BIO302 |
| Badge created with completion criteria | 10 | Badge named "Advanced Cell Biology Scholar" with `criteriatype=8` |
| Badge expiry set to 3 years | 5 | `expiretype=2` (relative) and `expireperiod` within 10% of 94,608,000 seconds |

## Database Tables Used

- `mdl_course_modules`: `completion`, `completionview`, `completionusegrade`, `completionpassgrade`
- `mdl_assign`: `completionsubmit`
- `mdl_forum`: `completionposts`
- `mdl_course_completion_criteria`: one row per activity criterion
- `mdl_badge`: `name`, `courseid`, `expireperiod`, `expiretype`
- `mdl_badge_criteria`: `criteriatype` (8 = course completion)
