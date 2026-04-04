# LibreOffice Calc Potluck Dish Conflict Resolver Task (`potluck_conflict_resolver@1`)

**Difficulty**: 🟡 Medium  
**Skills**: CSV import, conditional formulas, COUNTIF, SEARCH functions, data analysis  
**Duration**: 180 seconds  
**Steps**: ~15

## Overview

Manage the chaotic reality of community potluck coordination by importing a messy sign-up sheet, identifying problematic duplicate dishes within categories, calculating food quantity adequacy, flagging critical allergen concerns, and generating a balanced category summary.

## Scenario

You're organizing a neighborhood potluck for 40 people. Volunteers have been signing up with dishes, but you've heard there are problems: duplicate desserts, possible allergen concerns (peanuts), and maybe not enough main dishes. You need to analyze the sign-up sheet to identify these issues before the event.

## Starting State

- CSV file `potluck_signups.csv` contains volunteer submissions
- Data columns: Name, Dish, Category, Servings, Ingredients
- 15 sign-ups with known problems embedded in the data

## Required Actions

1. **Import CSV Data**
   - Open `potluck_signups.csv` in LibreOffice Calc
   - Verify columns imported correctly

2. **Add Duplicate Detection Column**
   - Create column "Duplicate Alert" or similar
   - Use COUNTIF to detect multiple dishes in same category
   - Example: `=IF(COUNTIF($C:$C, C2)>1, "CHECK: Multiple in category", "")`

3. **Calculate Total Servings**
   - Add cell with SUM formula: `=SUM(D:D)` for total servings
   - Calculate per-person ratio: `=TotalServings/40`

4. **Add Allergen Flagging Column**
   - Create column "Allergen Alert" or similar
   - Use SEARCH to detect "peanut" or "nut" in ingredients
   - Example: `=IF(OR(ISNUMBER(SEARCH("peanut",E2)), ISNUMBER(SEARCH("nut",E2))), "⚠ PEANUT RISK", "")`
   - Apply conditional formatting (red/yellow background)

5. **Create Category Distribution Summary**
   - Create summary section with category counts
   - Use COUNTIF for each category: Appetizer, Main, Side, Dessert
   - Flag imbalanced categories (e.g., >40% in one category)

6. **Apply Visual Formatting**
   - Highlight allergen alerts in red
   - Highlight duplicate conflicts in yellow/orange
   - Optional: Color-code categories

## Expected Results

- **Data Imported**: 15+ rows with 5 columns
- **Duplicate Detection**: Column with COUNTIF formula, 2+ rows flagged
- **Serving Calculations**: Total servings (~327) and per-person ratio (~8.2)
- **Allergen Alerts**: Column with SEARCH formula, 2 rows flagged (peanut dishes)
- **Category Summary**: COUNTIF counts showing 3 Appetizers, 3 Mains, 3 Sides, 6 Desserts

## Success Criteria

1. ✅ **Data Imported** - CSV data successfully imported with 15+ rows and 5 columns
2. ✅ **Duplicate Detection Active** - Column with COUNTIF-based alerts, 2+ rows flagged
3. ✅ **Serving Calculations Present** - Total servings and per-person ratio calculated
4. ✅ **Allergen Alerts Configured** - SEARCH-based allergen flagging, 1+ rows flagged
5. ✅ **Category Summary Created** - COUNTIF-based counts for all 4 categories

**Pass Threshold**: 70% (requires at least 3 out of 5 major criteria)

## Skills Tested

- CSV file import and handling
- Text functions (SEARCH, FIND)
- Logical functions (IF, OR, AND)
- Statistical functions (COUNTIF, SUM)
- Conditional formatting application
- Cell reference techniques (relative vs absolute)
- Data analysis and business logic

## Tips

- Use absolute references ($C:$C) in COUNTIF to prevent reference shifting
- SEARCH function is case-insensitive: `SEARCH("peanut", E2)`
- Multiple conditions: `OR(ISNUMBER(SEARCH("peanut",E2)), ISNUMBER(SEARCH(" nut",E2)))`
- Create summary section below or beside main data
- Conditional formatting: Format → Conditional Formatting → Condition
- Test formulas on one row, then copy down

## Real-World Context

This task reflects actual challenges in:
- Community event planning (PTA, neighborhood associations)
- Office party coordination
- Volunteer organization meal planning
- Wedding/celebration reception planning

Common frustrations addressed:
- "Why did four people bring desserts and nobody brought a main dish?"
- "I wish I'd known about the peanut allergy before accepting these dishes"
- "Do we have enough food for 40 people?"