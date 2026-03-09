# Gradebook Weighted Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Complex formulas, weighted averages, conditional logic, drop lowest score  
**Duration**: 300 seconds  
**Steps**: ~25

## Objective

Calculate final grades for students using a complex weighted grading system with special rules. This task tests advanced formula creation, nested functions, conditional logic, and understanding of academic grading policies.

## Task Description

The agent must:
1. Open a partially filled gradebook with raw scores across multiple categories
2. Calculate category averages (Tests, Homework, Quizzes, Participation)
3. Apply special rule: Drop the lowest quiz score when calculating quiz average
4. Calculate weighted final grade: 40% Tests + 30% Homework + 20% Quizzes + 10% Participation
5. Assign letter grades based on standard scale (A: 90-100, B: 80-89, C: 70-79, D: 60-69, F: 0-59)
6. Use formulas (not hardcoded values) for all calculations
7. Save the completed gradebook

## Grading Policy

**Category Weights:**
- Tests: 40%
- Homework: 30%
- Quizzes: 20% (DROP LOWEST QUIZ SCORE)
- Participation: 10%

**Letter Grade Scale:**
- A: 90-100%
- B: 80-89%
- C: 70-79%
- D: 60-69%
- F: 0-59%

## Expected Results

**Columns to Create:**
- **Column N**: Test Average (average of columns B-D)
- **Column O**: Homework Average (average of columns E-H)
- **Column P**: Quiz Average (average of I-L, excluding lowest score)
- **Column Q**: Participation (reference or copy from column M)
- **Column R**: Final Grade (%) (weighted calculation)
- **Column S**: Letter Grade (A-F based on final percentage)

**Example Formula for Quiz Average (Drop Lowest):**