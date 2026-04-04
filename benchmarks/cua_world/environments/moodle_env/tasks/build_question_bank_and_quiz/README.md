# Task: Build Question Bank and Quiz

## Overview

This task simulates the work of an Assessment Coordinator and University Mathematics Instructor who must populate a Moodle question bank and build a randomized mid-term examination. The agent must navigate Moodle's multi-layered question bank interface, create questions of different types (multiple choice and true/false), and then construct a quiz that draws random questions from specific question bank categories. This is a realistic, high-complexity workflow that requires understanding how Moodle's question bank integrates with the quiz module.

## Occupation

Assessment Coordinator / University Mathematics Instructor

## Target Environment

- Course: Probability and Statistics (MATH201), Engineering category
- Login: admin / Admin1234!
- Application URL: http://localhost/moodle

## Initial State

The MATH201 course exists in the Engineering category. The question bank for MATH201 already contains two empty categories:
- **Probability Basics** — no questions yet
- **Descriptive Statistics** — no questions yet

No quiz exists for this course.

## Target State

### Question Bank — Probability Basics (3 Multiple Choice Questions)

| # | Question Text | Correct Answer | Wrong Answers |
|---|--------------|----------------|---------------|
| Q1 | What is the probability of rolling a prime number on a standard 6-sided die? | 1/2 (primes are 2, 3, 5) | 1/3, 2/3, 1/6 |
| Q2 | If events A and B are independent with P(A) = 0.4 and P(B) = 0.3, what is P(A and B)? | 0.12 | 0.70, 0.10, 0.34 |
| Q3 | A standard deck has 52 cards. What is the probability of drawing a King? | 1/13 | 4/52, 1/4, 1/52 |

### Question Bank — Descriptive Statistics (2 True/False Questions)

| # | Question Text | Correct Answer |
|---|--------------|----------------|
| Q4 | The mean of a dataset is always equal to the median. | False |
| Q5 | Standard deviation is always a non-negative value. | True |

### Quiz — MATH201 Mid-Term Examination

| Setting | Value |
|---------|-------|
| Name | MATH201 Mid-Term Examination |
| Time limit | 45 minutes |
| Maximum attempts | 1 |
| Grade to pass | 60 out of 100 |
| Shuffle questions | Enabled |
| Shuffle answers within questions | Enabled |
| Question sources | 2 random from Probability Basics + 2 random from Descriptive Statistics |

## Steps the Agent Must Perform

1. Log in to Moodle as admin
2. Navigate to the MATH201 course
3. Open the Question Bank (via More menu or admin panel)
4. Navigate to the "Probability Basics" category
5. Create 3 multiple-choice questions with the specified text, correct answer, and wrong answer choices
6. Navigate to the "Descriptive Statistics" category
7. Create 2 true/false questions with the specified text and correct answer
8. Return to the MATH201 course page
9. Add a Quiz activity named "MATH201 Mid-Term Examination"
10. Configure: time limit 45 minutes, attempts 1, grade to pass 60, shuffle questions on
11. Add a random question slot drawing 2 questions from "Probability Basics"
12. Add a random question slot drawing 2 questions from "Descriptive Statistics"
13. Save the quiz

## Verification Criteria (100 points)

| Criterion | Points | Database Check |
|-----------|--------|----------------|
| Both question bank categories found in MATH201 context | 10 (5 each) | mdl_question_categories WHERE contextid = MATH201 context |
| Probability Basics has 3+ questions | 15 | COUNT mdl_question WHERE category = prob_cat_id AND qtype != 'random' |
| All 3 Probability Basics questions are multichoice type | 5 | COUNT mdl_question WHERE qtype = 'multichoice' |
| Descriptive Statistics has 2+ questions | 10 | COUNT mdl_question WHERE category = stat_cat_id AND qtype != 'random' |
| Both Descriptive Statistics questions are truefalse type | 5 | COUNT mdl_question WHERE qtype = 'truefalse' |
| Quiz "MATH201 Mid-Term Examination" created | 15 | mdl_quiz WHERE course = MATH201 AND name LIKE '%mid%term%' |
| Quiz time limit = 45 minutes (2700s, ±5 min tolerance) | 10 | mdl_quiz.timelimit BETWEEN 2640 AND 2760 |
| Quiz max attempts = 1 | 10 | mdl_quiz.attempts = 1 |
| Quiz has 4 total slots OR 2+ random slots | 15 | COUNT mdl_quiz_slots WHERE quizid = quiz_id |
| Both categories represented in random draws | 5 | mdl_question WHERE qtype = 'random' linked to each category |

**Pass threshold: 60 points**

## Why This Task is Difficult

1. **Nested navigation**: The question bank is accessed through a separate interface (Course Administration > Question Bank), not the course page directly. Each category must be navigated to individually.

2. **Two question types**: The agent must create both multiple-choice questions (with 4 choices, exactly one correct) and true/false questions — each using different Moodle form interfaces.

3. **Random question configuration**: After creating the quiz, the agent must configure random question draws from specific bank categories. In Moodle 4.x, this is done through the "Add random question" interface in the quiz editor, which requires selecting the source category from a dropdown. This is distinct from adding specific questions.

4. **Category-level targeting**: The random draws must reference the specific named categories ("Probability Basics", "Descriptive Statistics") rather than a default or top-level category.

5. **Multiple quiz settings**: Time limit, attempts, grade to pass, and shuffle options must all be configured correctly in one form submission.

6. **Moodle 4.x interface changes**: Moodle 4.5 significantly redesigned the question bank and quiz builder interface compared to earlier versions, requiring knowledge of the new navigation patterns.

## Database Schema Reference

- `mdl_question_categories`: id, name, contextid, parent — organizes questions by context
- `mdl_question`: id, category, qtype ('multichoice', 'truefalse', 'random'), name, questiontext
- `mdl_quiz`: id, course, name, timelimit (seconds), attempts (0=unlimited), shuffleanswers
- `mdl_quiz_slots`: id, quizid, slot, questionid — links questions (or random placeholders) to quiz
- `mdl_grade_items`: itemtype='mod', itemmodule='quiz', iteminstance=quiz_id, gradepass
- `mdl_context`: id, contextlevel=50 (course level), instanceid=course_id

## Edge Cases

- `mdl_quiz.timelimit` stores seconds (45 min = 2700 seconds)
- `mdl_quiz.attempts = 0` means unlimited; expected value is 1
- Random question slots appear as `mdl_question.qtype = 'random'` in older Moodle; in Moodle 4.x they may use `mdl_quiz_slots` with a reference to `mdl_quiz_random_question_set`
- Question bank categories must belong to the course context (`contextlevel=50`), not the system context
- The verifier is lenient on random question detection since SQL detection of Moodle 4.x random slots may vary
