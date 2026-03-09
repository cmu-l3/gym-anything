# LibreOffice Calc Home Renovation Budget Tracker Task (`renovation_budget_variance@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Budget variance analysis, percentage calculations, conditional formatting, SUM functions  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Manage a home renovation budget tracking spreadsheet where you need to analyze cost overruns and identify problem areas. Calculate budget variances (actual costs vs planned budget), compute percentage overages, identify total spending, and highlight over-budget categories using conditional formatting.

## Task Description

The agent must:
1. Open the provided renovation budget spreadsheet with Budget and Actual columns
2. Create a "Variance ($)" column that calculates: Actual - Budget
3. Create a "% Over Budget" column that calculates: (Variance / Budget) * 100
4. Add SUM formulas to calculate totals for Budget, Actual, and Variance
5. Apply conditional formatting to highlight over-budget items (positive variance) in red
6. Format currency and percentage columns appropriately

## Starting Data

| Category   | Budget | Actual | Variance ($) | % Over Budget |
|------------|--------|--------|--------------|---------------|
| Plumbing   | 3500   | 4200   | (empty)      | (empty)       |
| Electrical | 2800   | 2650   | (empty)      | (empty)       |
| Flooring   | 4500   | 5800   | (empty)      | (empty)       |
| Cabinets   | 8000   | 8000   | (empty)      | (empty)       |
| Paint      | 1200   | 980    | (empty)      | (empty)       |
| Fixtures   | 2400   | 2890   | (empty)      | (empty)       |
| Labor      | 6000   | (empty)| (empty)      | (empty)       |
| Permits    | 800    | 750    | (empty)      | (empty)       |
| **Total**  | (empty)| (empty)| (empty)      | -             |

Note: Labor has no Actual value yet (project in progress).

## Expected Results

- **D2:D9** contain variance formulas (=C2-B2, etc.)
- **E2:E9** contain percentage formulas (=D2/B2*100 or =D2/B2)
- **B10, C10, D10** contain SUM formulas for totals
- **D2:D9** have conditional formatting (red background/text for positive values)
- **Currency formatting** applied to Budget, Actual, Variance columns
- **Percentage formatting** applied to % Over Budget column

## Verification Criteria

1. ✅ **Variance Formulas**: Column D contains correct formulas (=C#-B#)
2. ✅ **Percentage Formulas**: Column E contains correct formulas (=D#/B#*100)
3. ✅ **Total Formulas**: Row 10 contains SUM formulas
4. ✅ **Conditional Formatting**: Variance column highlights over-budget items
5. ✅ **Correct Calculations**: Spot-check calculations match expected values
6. ✅ **Currency Formatting**: B, C, D columns formatted as currency
7. ✅ **No Errors**: No #DIV/0!, #REF!, or similar formula errors

**Pass Threshold**: 70% (5/7 criteria must pass)

## Skills Tested

- Formula creation and cell references
- Arithmetic operations (subtraction, division, multiplication)
- SUM function usage
- Formula copying (relative references)
- Conditional formatting application
- Number formatting (currency, percentage)
- Budget variance analysis concepts

## Real-World Context

Home renovations notoriously go over budget. This spreadsheet helps homeowners:
- Quantify how much over budget they are
- Identify which categories are causing the most overruns
- Assess severity of overages as percentages
- Make informed decisions about where to cut costs

## Tips

- Start with variance formulas: =C2-B2 (Actual minus Budget)
- Copy formulas down using fill handle or Ctrl+C/Ctrl+V
- For percentages: =(D2/B2)*100 or format =D2/B2 as percentage
- Use Format → Conditional Formatting to highlight positive variances
- Total row should use =SUM(B2:B9) for Budget, similar for others
- Format as currency: Right-click → Format Cells → Currency