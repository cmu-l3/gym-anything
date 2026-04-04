# Soccer Snack Schedule Organizer Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, sorting, conditional formatting, formulas, data validation  
**Duration**: 300 seconds  
**Steps**: ~15

## Objective

Clean up and organize a messy youth soccer team snack schedule inherited from a previous parent volunteer. The spreadsheet contains inconsistent name formatting, duplicate assignments, missing families, out-of-order dates, and unclear allergen information. Transform this chaos into a professional, shareable schedule.

## Task Scenario

**Context:** You're a parent volunteer who just took over snack coordination for your child's U10 soccer team (12 families, 14-game season). The previous coordinator left you a messy spreadsheet. The coach requires documented allergen tracking, and parents are asking who's bringing snacks for Saturday's game. You need to clean this up URGENTLY.

## Starting Data Issues

The inherited CSV has multiple problems:
- **Inconsistent names**: Mix of first names only, last names only, "Family" suffix variations
- **Duplicate assignments**: Some families assigned twice while others aren't assigned at all
- **Missing families**: Not all 12 families are represented
- **Out-of-order dates**: Games not in chronological sequence
- **Hidden allergen info**: Allergen requirements exist but aren't visually highlighted

## Required Actions

1. **Standardize family names** to consistent format (e.g., "LastName Family")
2. **Sort data chronologically** by game date
3. **Fix duplicate assignments** - reassign duplicates to missing families
4. **Add cost estimate column** with $25 per week formula
5. **Apply conditional formatting** to highlight allergen-awareness weeks
6. **Create fairness check** using COUNTIF to count assignments per family
7. **Calculate total season cost** with SUM formula
8. **Format for readability** (adjust widths, bold headers, proper alignment)

## Expected Results

After cleanup:
- All family names follow consistent format
- Dates sorted chronologically (earliest to latest)
- All 12 families assigned at least once, none more than twice
- New "Est. Cost" column showing $25 per week
- Allergen weeks visually highlighted (red/orange/bold)
- Summary section showing assignment count per family
- Total season cost calculated (~$350 for 14 weeks)

## Success Criteria

1. ✅ **Names Standardized**: Family names follow consistent pattern (≥90%)
2. ✅ **No Excessive Duplicates**: No family assigned >2 times
3. ✅ **Complete Coverage**: All 14 weeks have assigned families
4. ✅ **Chronologically Sorted**: Dates in ascending order
5. ✅ **Cost Column Present**: Numeric currency values exist
6. ✅ **Total Cost Calculated**: SUM formula correctly totals costs
7. ✅ **Conditional Formatting Applied**: Allergen cells visibly highlighted
8. ✅ **Fairness Check Exists**: COUNTIF or count per family visible

**Pass Threshold**: 75% (6 out of 8 criteria must pass)

## Skills Tested

- Data cleaning and standardization
- Find & Replace operations
- Chronological sorting with dates
- Formula creation (SUM, COUNTIF)
- Conditional formatting rules
- Column operations and formatting
- Duplicate detection and resolution
- Data validation and quality assessment

## Tips

- Use Find & Replace (Ctrl+H) to standardize name formats
- Sort by selecting data range: Data → Sort, choose Date column
- Conditional formatting: Format → Conditional Formatting → Condition
- COUNTIF syntax: `=COUNTIF(B:B, "Smith Family")` counts occurrences
- Remember to bold headers and adjust column widths for readability