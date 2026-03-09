# Task: Create Quiz with Questions

## Overview
Create a timed multiple-choice quiz in the BIO101 course. This is a core instructor workflow — teachers regularly create quizzes with specific settings (time limits, attempt restrictions) and add questions with correct/incorrect answer choices.

## Target
- Course: Introduction to Biology (BIO101)
- Login: admin / Admin1234!
- Application URL: http://localhost/moodle

## Task Description
1. Log in to Moodle as admin
2. Navigate to BIO101 course
3. Turn editing on
4. Add a Quiz activity:
   - Name: "Midterm Exam: Cell Biology"
   - Description: cell biology unit exam
   - Time limit: 60 minutes
   - Attempts allowed: 1
5. Add Question 1 (Multiple Choice):
   - Name: "Powerhouse of the Cell"
   - Text: "Which organelle is known as the powerhouse of the cell?"
   - Choices: Nucleus, Mitochondria (correct), Ribosome, Golgi apparatus
6. Add Question 2 (Multiple Choice):
   - Name: "Basic Unit of Life"
   - Text: "What is the basic unit of life?"
   - Choices: Atom, Molecule, Cell (correct), Organ
7. Save quiz with both questions

## Success Criteria (100 points)
| Criterion | Points | Check |
|-----------|--------|-------|
| Quiz exists and newly created in BIO101 | 20 | mdl_quiz count increased, course_id matches |
| Quiz name matches | 20 | LIKE '%midterm%cell biology%' |
| Time limit = 3600s (60 min) | 20 | mdl_quiz.timelimit |
| Attempts = 1 | 20 | mdl_quiz.attempts |
| 2+ questions added | 20 | mdl_quiz_slots count |

Pass threshold: 60 points (must include quiz created + correct name)

## Verification Strategy
- **Baseline**: Record initial quiz count in BIO101 via `setup_task.sh`
- **Wrong-target rejection**: Verify quiz.course matches BIO101 course_id (score=0 if wrong)
- **Export**: Query mdl_quiz, mdl_quiz_slots from database
- **Partial credit**: Points for each setting configured correctly

## Database Schema
- `mdl_quiz`: id, course, name, timelimit (seconds), attempts (0=unlimited)
- `mdl_quiz_slots`: quizid, slot (links questions to quiz)
- `mdl_course`: id, shortname='BIO101'

## Edge Cases
- Quiz timelimit stored in seconds (60 min = 3600)
- Attempts=0 means unlimited in Moodle
- Moodle 4.5 question bank uses mdl_question_references (not direct FK)
