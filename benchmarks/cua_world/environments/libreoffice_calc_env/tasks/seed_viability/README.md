# LibreOffice Calc Seed Library Viability Checker Task (`seed_viability@1`)

## Overview

This task challenges an agent to assess the viability of seeds in a community seed library by calculating seed age, comparing against known shelf life data, and flagging seeds that need testing or should be discarded. The agent must work with date calculations, conditional formulas, and data validation to help a seed library coordinator prepare for the upcoming spring planting season.

## Rationale

**Why this task is valuable:**
- **Real-World Context:** Community seed libraries and seed swaps are increasingly popular sustainability initiatives where gardeners save and exchange seeds
- **Date Arithmetic Skills:** Tests ability to calculate time spans and compare dates (crucial for expiration tracking, age calculations, scheduling)
- **Conditional Logic Mastery:** Requires multi-condition IF statements that mirror real decision-making processes
- **Data Integration:** Combines information from multiple sources (seed inventory + reference data about seed lifespans)
- **Quality Assessment Workflow:** Represents common data auditing tasks where records must be evaluated against criteria
- **Visual Data Validation:** Uses conditional formatting to quickly identify data quality issues

**Scenario Context:** 
A community garden's seed library coordinator receives seed donations from members. Seeds are only useful if they're still viable (able to germinate). Different seed types have different shelf lives - tomato seeds last 4-6 years, lettuce only 1-3 years, etc. The coordinator has a spreadsheet with donated seeds and their collection dates, but needs help determining which seeds are:
- **Good**: Still within expected shelf life, ready to distribute
- **Test**: Approaching end of shelf life, need germination testing before distribution  
- **Discard**: Too old to be reliably viable, should be composted

## Skills Required

### A. Interaction Skills
- Multi-cell formula entry
- Formula copying (fill-down)
- Sheet navigation (multiple sheets)
- Conditional formatting dialog
- Date format recognition
- Column insertion

### B. Calc Knowledge
- Date functions (TODAY, DATEDIF, YEAR)
- Conditional logic (IF statements)
- Lookup functions (VLOOKUP, INDEX/MATCH)
- Comparison operators
- Conditional formatting
- Sheet references

### C. Task-Specific Skills
- Age calculation from dates
- Threshold comparison
- Multi-criteria decision making
- Data quality assessment
- Visual pattern recognition

## Task Steps

1. **Examine the Seed Inventory** - Review seed data with empty Age_Years and Viability_Status columns
2. **Review Reference Data** - Understand seed lifespan thresholds in second sheet
3. **Calculate Seed Age** - Use date formulas to compute years since collection
4. **Look Up Lifespan Data** - Use VLOOKUP/INDEX to retrieve min/max viable years
5. **Determine Viability Status** - Create nested IF formula for Good/Test/Discard logic
6. **Apply Conditional Formatting** - Color-code status values (Green/Yellow/Red)
7. **Verify Results** - Check calculations and ensure no errors
8. **Save the File** - Save as seed_viability_checked.ods

## Success Criteria

- ✅ **Age Calculated:** Age_Years column contains date formulas
- ✅ **Viability Logic Correct:** Status reflects seed age vs. lifespan thresholds
- ✅ **Reference Data Used:** Formulas pull from reference sheet via lookups
- ✅ **Conditional Formatting Applied:** Visual color coding present
- ✅ **No Errors:** Calculations complete without formula errors
- ✅ **Spot Checks Pass:** Manual validation confirms accurate classification

**Pass Threshold:** 70% (4 out of 6 criteria)