# Task: Create Choice Activity

## Overview
Create a poll (Choice activity) in the CS110 course to survey students about their preferred programming language. This is a common instructor workflow for gathering student preferences, forming project teams, or conducting quick polls at the start of a course.

## Target
- Course: Computer Science Fundamentals (CS110)
- Login: admin / Admin1234!
- Application URL: http://localhost/moodle

## Task Description
1. Log in to Moodle as admin
2. Navigate to CS110 course
3. Turn editing on
4. Add a "Choice" activity:
   - Name: "Preferred Programming Language"
   - Description: survey for course project team formation
   - Option 1: "Python"
   - Option 2: "Java"
   - Option 3: "C++"
   - Option 4: "JavaScript"
5. Settings:
   - Allow choice to be updated: Yes
   - Publish results: Always show results to students
6. Save and return to course

## Success Criteria (100 points)
| Criterion | Points | Check |
|-----------|--------|-------|
| Choice exists and newly created in CS110 | 20 | mdl_choice count increased, course matches |
| Activity name matches | 15 | LIKE '%preferred%programming%language%' |
| Has at least 4 options | 15 | mdl_choice_options COUNT |
| All 4 languages present | 25 | Python, Java, C++, JavaScript in options |
| Allow update enabled | 10 | mdl_choice.allowupdate = 1 |
| Show results = Always (3) | 15 | mdl_choice.showresults = 3 |

Pass threshold: 60 points (must have choice created)

## Verification Strategy
- **Baseline**: Record initial choice activity count in CS110
- **Wrong-target rejection**: Verify choice.course matches CS110 course_id (score=0 if wrong)
- **Options check**: Query mdl_choice_options and match each language (case-insensitive)
- **Partial credit**: 6 points per language found; 7 points for 2+ options; 7 for partial name match

## Database Schema
- `mdl_choice`: id, course, name, intro, allowupdate (0/1), showresults (0-3)
  - showresults: 0=Do not publish, 1=After answering, 2=After closing, 3=Always
- `mdl_choice_options`: id, choiceid, text

## Edge Cases
- CS110 has no teacher enrolled; admin has site-level access to add activities
- "Java" vs "JavaScript" disambiguation: exact match query for "java" without "script"
- C++ option text must match literally (not "Cpp" or "C plus plus")
