# Music Teacher Practice Log Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, conditional logic, data analysis, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Analyze student practice logs for a music teacher by calculating totals, goal completion percentages, and status categories. Apply conditional formatting to highlight students needing attention. This task tests intermediate formula skills, conditional logic, and data visualization.

## Task Description

The agent must:
1. Open a practice log spreadsheet with student data (Name, Weekly Goal, Week 1-4 minutes)
2. Calculate "Total Practice (4 weeks)" using SUM formula
3. Calculate "Total Goal (4 weeks)" (Weekly Goal × 4)
4. Calculate "% of Goal Achieved" ((Total Practice / Total Goal) × 100)
5. Create "Status" column using IF formula with thresholds:
   - "Excellent" if ≥100%
   - "On Track" if 80-99%
   - "Needs Encouragement" if 50-79%
   - "Urgent Check-in" if <50%
6. Calculate "Weeks Reported" using COUNTA
7. Calculate "Weeks Goal Met" using COUNTIF
8. Apply conditional formatting to % column (green for high, red for low)
9. Create summary statistics (optional): total students, average %, category counts

## Starting Data

The spreadsheet contains 12 students with:
- Varied weekly goals (60, 90, 120, 150 minutes based on level)
- 4 weeks of reported practice minutes
- Some missing data (students who didn't report)
- Mix of high achievers, struggling students, and declining engagement

## Expected Results

- **Column F (Total Practice)**: =SUM(C2:F2) for each student
- **Column G (Total Goal)**: =B2*4 for each student
- **Column H (% of Goal)**: =(F2/G2)*100 for each student
- **Column I (Status)**: =IF(H2>=100,"Excellent",IF(H2>=80,"On Track",IF(H2>=50,"Needs Encouragement","Urgent Check-in")))
- **Column J (Weeks Reported)**: =COUNTA(C2:F2)
- **Column K (Weeks Goal Met)**: =COUNTIF(C2:F2,">="&B2)
- **Conditional formatting** on column H (% of Goal)

## Verification Criteria

1. ✅ **Total Practice Calculated**: SUM formulas present and accurate
2. ✅ **Goal Percentage Calculated**: Division formulas accurate (±1% tolerance)
3. ✅ **Status Assigned**: IF formulas with correct thresholds
4. ✅ **Consistency Metrics**: COUNTA and COUNTIF formulas present
5. ✅ **Conditional Formatting**: Visual highlighting applied to % column
6. ✅ **Sample Validation**: 3 students' calculations verified manually

**Pass Threshold**: 70% (4/6 criteria must pass)

## Skills Tested

- SUM, COUNTIF, COUNTA functions
- IF nested conditional logic
- Percentage calculations
- Cell references (absolute vs relative)
- Conditional formatting rules
- Multi-column formula workflow
- Data analysis and pattern recognition

## Real-World Context

Music teacher Mrs. Rodriguez needs to identify which students need encouragement before next week's lessons. Currently takes 45 minutes to manually review emails. This analysis reduces it to 5 minutes of reviewing flagged students.

## Tips

- Start with formulas in first data row, then copy down
- Use relative references for row numbers, absolute for column headers
- Test IF formula logic: 100%, 80%, 50% thresholds
- Conditional formatting: Format → Conditional → Color Scale or Condition
- COUNTIF syntax: =COUNTIF(range, criteria)
- Handle missing data: COUNTA counts non-empty cells