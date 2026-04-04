# Task: Post Forum Announcement

## Overview
Post a welcome announcement in the BIO101 course's Announcements forum. This is the most common instructor communication task — every course starts with a welcome message that outlines expectations, schedule, and contact information.

## Target
- Course: Introduction to Biology (BIO101)
- Forum: Announcements (type='news', created by default in every Moodle course)
- Login: admin / Admin1234!
- Application URL: http://localhost/moodle

## Task Description
1. Log in to Moodle as admin
2. Navigate to BIO101 course
3. Find and open the "Announcements" forum
4. Add a new discussion topic:
   - Subject: "Welcome to Introduction to Biology - Spring 2026"
   - Message: welcome text mentioning BIO101, cell biology, genetics, ecology, syllabus, office hours
5. Post the discussion

## Success Criteria (100 points)
| Criterion | Points | Check |
|-----------|--------|-------|
| Post found in announcements forum | 20 | mdl_forum_posts JOIN mdl_forum_discussions |
| Post in correct course (BIO101) | 15 | mdl_forum_discussions.course matches |
| Subject matches (welcome + biology) | 25 | keyword matching on post subject |
| Message contains key content | 25 | keywords: biology, cell biology, syllabus, office hours |
| Discussion count increased | 15 | baseline comparison |

Pass threshold: 60 points (must have post found + correct course)

## Verification Strategy
- **Baseline**: Record initial discussion count in BIO101's announcements forum (type='news')
- **Wrong-target rejection**: Verify post_forum_course matches expected_course_id (score=0 if wrong)
- **Content check**: grep for keywords in message (biology, cell biology, syllabus, office hours, genetics/ecology)
- **Partial credit**: Subject with just "welcome" or just "biology" gets 12 points

## Database Schema
- `mdl_forum`: id, course, type ('news' = announcements)
- `mdl_forum_discussions`: id, forum, course, name, userid
- `mdl_forum_posts`: id, discussion, parent (0=first post), userid, subject, message

## Edge Cases
- Announcements forum has type='news' (not 'general')
- Message stored as HTML in mdl_forum_posts.message — keyword grep works on raw content
- Post truncated to 500 chars for JSON export to avoid escaping issues
