# LibreOffice Calc Grade Calculator Task (`grade_whatif_calculator@1`)

## Overview

This task tests an agent's ability to calculate weighted grades from multiple categories and perform "what-if" analysis to determine required scores on remaining assignments. The scenario mirrors a common student anxiety: mid-semester, knowing current grades across different weighted categories (homework, quizzes, exams), and desperately figuring out what score is needed on the final exam to achieve a desired overall grade. The agent must use weighted average formulas and solve for unknown future scores.

## Rationale

**Why this task is valuable:**
- **Real-world Stress Scenario:** Captures authentic student experience of grade anxiety and academic planning
- **Weighted Average Mastery:** Tests understanding of weighted calculations, not simple means
- **Formula Logic:** Requires creating formulas that reference other calculated cells
- **What-if Analysis:** Teaches goal-seeking through formula manipulation
- **Practical Math Application:** Connects abstract percentages to real-world consequences
- **Error-prone Calculation:** Students commonly miscalculate weighted grades, making this a valuable skill

**Skill Progression:** This task bridges basic formulas (SUM, AVERAGE) with more sophisticated weighted calculations and conditional logic, representing intermediate-level spreadsheet work.

## Skills Required

### A. Interaction Skills
- Cell navigation and efficient movement between sections
- Formula entry with complex cell references and arithmetic operators
- Proper use of parentheses for order of operations
- Understanding of absolute vs. relative cell references

### B. Calc Knowledge
- Weighted average calculation concepts
- Formula debugging and verification
- Percentage arithmetic (decimals vs. percentages)
- Cell formatting for percentages

### C. Task-Specific Skills
- Understanding weighted grade systems
- Algebraic thinking to solve for unknown values
- Verification that calculations produce expected results

## Starting State

The spreadsheet opens with:
- **Homework section:** 5 completed assignments (95, 88, 92, 100, 85) - worth 20%
- **Quiz section:** 4 completed quizzes (82, 90, 78, 88) - worth 20%
- **Midterm Exam:** 1 score (84) - worth 25%
- **Final Exam:** Not yet taken - worth 35%
- **Target Grade:** 90% (A grade)

Some cells have formulas already (category averages), but key cells are empty.

## Expected Results

After task completion:
- **Cell B21 (Current Grade):** Formula calculating weighted average of completed work → ~56.3%
- **Cell B23 (Needed on Final):** Formula calculating required final exam score → ~96.3%
- Both formulas should use cell references, not hardcoded values

## Verification Criteria

1. ✅ **Current Grade Formula Present:** Cell B21 contains a formula (not hardcoded)
2. ✅ **Current Grade Accurate:** Calculated value is approximately 56.3% (±1%)
3. ✅ **Needed Score Formula Present:** Cell B23 contains a formula
4. ✅ **Needed Score Accurate:** Calculated value is approximately 96.3% (±1%)
5. ✅ **Algebraic Verification:** The needed score, when plugged into grade calculation, produces the target grade (±1%)

**Pass Threshold**: 75% (requires at least 4 out of 5 criteria)

## Task Steps

1. **Examine the gradebook** - Understand the structure and weights
2. **Verify category averages** - Check that homework and quiz averages are calculated
3. **Calculate current grade** - Create weighted average formula for completed work in B21
4. **Calculate needed final score** - Create algebraic formula in B23 to solve for required score
5. **Verify your work** - Check that the math adds up correctly

## Tips

- Current grade formula: `=(B9*0.2)+(B16*0.2)+(B18*0.25)`
- Needed final formula: `=(B22-B21)/0.35`
- Use cell references (B9, B16, etc.), not hardcoded values
- Remember to account for weights (20% = 0.20, 35% = 0.35)
- The target grade is in cell B22 (90)

## Skills Tested

- Weighted average calculations
- Formula construction with cell references
- Algebraic reasoning (solving for unknown)
- Percentage arithmetic
- Formula verification and debugging