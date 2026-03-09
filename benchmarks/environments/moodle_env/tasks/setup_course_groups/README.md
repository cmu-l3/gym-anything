# Task: Setup Course Groups

## Overview
Create student discussion groups in the HIST201 course and configure the group mode. This is a standard instructor workflow for facilitating collaborative learning — teachers create groups, assign students, and set the course to use separate group spaces.

## Target
- Course: World History (HIST201)
- Students: Bob Brown (bbrown), Carol Garcia (cgarcia), David Lee (dlee)
- Login: admin / Admin1234!
- Application URL: http://localhost/moodle

## Task Description
1. Log in to Moodle as admin
2. Navigate to HIST201 course
3. Go to Participants > Groups (or course admin > Groups)
4. Create "Discussion Group A":
   - Description: "Group for discussing ancient civilizations topics"
   - Add members: bbrown, cgarcia
5. Create "Discussion Group B":
   - Description: "Group for discussing modern history topics"
   - Add member: dlee
6. Edit course settings → Groups → Group mode → "Separate groups"
7. Save

## Success Criteria (100 points)
| Criterion | Points | Check |
|-----------|--------|-------|
| Discussion Group A exists | 15 | mdl_groups WHERE name LIKE '%Discussion Group A%' |
| Discussion Group B exists | 15 | mdl_groups WHERE name LIKE '%Discussion Group B%' |
| bbrown + cgarcia in Group A | 25 | mdl_groups_members join mdl_user |
| dlee in Group B | 20 | mdl_groups_members join mdl_user |
| Course group mode = Separate (1) | 25 | mdl_course.groupmode |

Pass threshold: 70 points (must have both groups created)

## Verification Strategy
- **Baseline**: Record initial group count in HIST201
- **Member check**: Join mdl_groups_members with mdl_user by username
- **Partial credit**: 12 points if only one Group A member assigned; 15 for Visible groups instead of Separate

## Database Schema
- `mdl_groups`: id, courseid, name, description
- `mdl_groups_members`: groupid, userid
- `mdl_course`: id, groupmode (0=No groups, 1=Separate, 2=Visible)
- `mdl_user`: id, username (bbrown, cgarcia, dlee)

## Edge Cases
- Students must already be enrolled in HIST201 (bbrown, cgarcia, dlee are per setup_moodle.sh)
- Visible groups (2) gets partial credit vs Separate groups (1)
