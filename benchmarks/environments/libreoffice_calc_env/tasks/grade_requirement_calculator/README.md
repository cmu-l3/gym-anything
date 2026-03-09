# Grade Requirement Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Weighted averages, conditional logic, goal-seeking calculations, formula creation  
**Duration**: 180 seconds  
**Steps**: ~12

## Objective

Help a college student calculate what scores they need on remaining assignments to achieve their target final grade. This task tests advanced formula creation including weighted averages, handling dropped scores, and working backwards from desired outcomes.

## Scenario

Sarah is taking Statistics 201 and wants to earn a B+ (87%) in the course. She has completed most assignments but still has her final project and final exam remaining. She needs to know what scores she needs on these remaining assignments to achieve her goal.

## Task Description

The agent must:
1. Open a spreadsheet with Sarah's grade data
2. Calculate her current weighted grade from completed work
3. Calculate the average homework score (excluding the lowest score)
4. Calculate the average quiz score
5. Determine what score she needs on the final exam (assuming 90% on project)
6. Verify if the target grade is achievable

## Grading Categories

- **Homework**: 25% (7 assignments, drop lowest)
- **Quizzes**: 15% (5 quizzes, no drops)
- **Midterm Exam**: 20% (completed: 82%)
- **Project**: 15% (not yet submitted)
- **Final Exam**: 25% (not yet taken)

## Completed Work

**Homework scores**: 90%, 76%, 84%, 70%, 96%, [blank], [blank]
**Quiz scores**: 90%, 85%, 80%, 95%, [blank]
**Midterm**: 82%

## Expected Results

- **Homework Average** cell should calculate average excluding lowest score
- **Quiz Average** cell should calculate average of completed quizzes
- **Current Weighted Grade** cell should combine completed categories
- **Required Final Score** cell should calculate needed final exam score (given project score assumption)

## Verification Criteria

1. ✅ **Current Weighted Grade Correct**: Formula accurately calculates current standing (±0.5%)
2. ✅ **Homework Drop Rule Applied**: Lowest homework score properly excluded from average
3. ✅ **Required Final Score Calculated**: Formula correctly computes needed final exam score
4. ✅ **Mathematical Feasibility Check**: Agent identifies if target grade is achievable
5. ✅ **Formula Structure Valid**: Uses proper functions (not hardcoded numbers)

**Pass Threshold**: 80% (4/5 criteria must pass)

## Skills Tested

- Weighted average calculations
- Conditional logic for dropped scores
- Cell references (absolute and relative)
- Nested formulas
- Goal-seeking logic
- Mathematical reasoning

## Tips

- Use `=AVERAGE()` for simple averages
- To exclude lowest: `=(SUM(range) - MIN(range)) / (COUNT(range) - 1)`
- For weighted grade: multiply each category average by its weight
- Required score formula: solve algebraically for the unknown variable
- Check if required score > 100% (unachievable)