# Insurance Quote Comparison Task

**Difficulty**: 🟡 Medium  
**Skills**: Data entry, formula creation, period conversion, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Organize and compare insurance quotes from multiple providers with different billing periods. Create a comparison spreadsheet that normalizes all costs to annual amounts, calculates totals, and highlights the most cost-effective option using conditional formatting.

## Task Description

The agent must:
1. Open a new LibreOffice Calc spreadsheet
2. Create a structured comparison table with headers
3. Enter insurance quote data from 3 providers (different billing periods)
4. Create formulas to convert all costs to annual basis
5. Calculate total annual cost for each provider
6. Apply conditional formatting to highlight the cheapest option
7. Save the file

## Insurance Quote Data

### SafeDrive Insurance
- Liability: $85/month
- Comprehensive: $320/semi-annual
- Collision: $450/annual

### QuickQuote Auto
- Liability: $78/month
- Comprehensive: $340/semi-annual
- Collision: $475/annual

### BudgetShield Cars
- Liability: $92/month
- Comprehensive: $295/semi-annual
- Collision: $425/annual

## Expected Calculations

Annual cost conversions:
- Monthly → Annual: multiply by 12
- Semi-annual → Annual: multiply by 2
- Annual → Annual: use as-is

**Expected Annual Totals:**
- SafeDrive Insurance: (85×12) + (320×2) + 450 = $2,110
- QuickQuote Auto: (78×12) + (340×2) + 475 = $2,091 ✓ (Cheapest)
- BudgetShield Cars: (92×12) + (295×2) + 425 = $2,119

## Verification Criteria

1. ✅ **Data Entry**: All provider names and base premium values entered correctly
2. ✅ **Formulas Present**: Annual conversion formulas exist (multiply by 12, 2, or 1)
3. ✅ **Calculations Correct**: Total annual costs match expected values (±$5 tolerance)
4. ✅ **Formatting Applied**: Currency format and conditional highlighting present
5. ✅ **Minimum Identified**: QuickQuote Auto correctly highlighted as cheapest

**Pass Threshold**: 70% (requires accurate data entry and mostly correct calculations)

## Skills Tested

- Structured table design
- Data entry with mixed billing periods
- Period conversion formulas (monthly, semi-annual to annual)
- SUM formulas for totals
- Currency formatting
- Conditional formatting (highlight minimum value)
- Decision-support tool creation

## Suggested Table Structure
