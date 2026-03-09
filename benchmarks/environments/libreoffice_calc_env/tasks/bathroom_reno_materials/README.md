# LibreOffice Calc Bathroom Renovation Materials Calculator Task (`bathroom_reno_materials@1`)

## Overview

This task tests an agent's ability to work with messy real-world measurement data from a DIY home renovation project. The agent must standardize mixed measurement units, calculate material quantities with appropriate waste factors, round up to purchasable package units, and flag items that would exceed budget. This represents a common scenario where homeowners plan renovations using spreadsheets with data collected from multiple sources (tape measures, online specs, store catalogs) in inconsistent formats.

## Rationale

**Why this task is valuable:**
- **Real-world Data Messiness:** Tests ability to work with inconsistent measurement units (decimal feet, metric)
- **Practical Domain Knowledge:** Requires understanding construction waste factors and package rounding
- **Multi-step Calculation Workflow:** Combines unit conversion → area calculation → waste adjustment → rounding → cost calculation
- **Decision Logic:** Flags budget overruns to enable prioritization decisions
- **Common Personal Finance Use Case:** Home renovation planning is a frequent spreadsheet application for non-technical users
- **Error-prone Domain:** Construction measurements are notorious for calculation mistakes that cost real money

**Skill Progression:** This task bridges basic arithmetic with real-world domain complexity, requiring both technical spreadsheet skills and practical reasoning about physical constraints.

## Skills Required

### A. Interaction Skills
- **Formula Creation:** Write multi-step formulas combining arithmetic, functions, and cell references
- **Function Application:** Use ROUNDUP, IF, and basic math functions appropriately
- **Cell Reference Management:** Create formulas that reference other calculated cells in logical sequence
- **Conditional Logic:** Implement IF statements to flag budget issues
- **Data Entry:** Input missing waste factor percentages
- **Column Operations:** Apply formulas consistently across rows

### B. LibreOffice Calc Knowledge
- **Function Syntax:** Understand ROUNDUP(value, decimals), IF(condition, true, false)
- **Order of Operations:** Construct formulas where calculations must happen in correct sequence
- **Relative vs Absolute References:** Use appropriate reference types for formulas copied down columns
- **Number Formatting:** Display currency and percentages appropriately
- **Conditional Display:** Show budget warnings based on calculation results

### C. Task-Specific Skills
- **Unit Conversion Logic:** Convert between decimal feet and metric measurements
- **Area Calculation:** Compute square footage from length × width measurements
- **Waste Factor Application:** Understand that material quantities need percentage increases for cutting waste
- **Package Rounding:** Recognize that materials come in discrete units (boxes, bags, rolls)
- **Budget Constraint Reasoning:** Identify when costs exceed limits and flag for user attention
- **Practical Construction Knowledge:** Understand why waste factors exist and typical percentages

## Human Context & Motivation

**The Scenario:**
Sarah is renovating her guest bathroom on a tight budget after getting sticker shock from contractor quotes. She's doing the work herself and has been measuring the space over several evenings. Her measurements are messy:

- Some measurements are in decimal feet (e.g., 5.25 ft)
- The Italian tile she wants has specs in centimeters (she copy-pasted from the website)
- She knows she needs "extra for waste" but isn't sure how much for each material
- She has a hard budget limit of $1,500 total (with per-item limits)

Sarah started a spreadsheet but got confused with the calculations. She needs help to:
1. Standardize all measurements to square footage
2. Apply proper waste factors (10-15% for tile, 5-10% for other materials)
3. Round up to full boxes/units since stores don't sell partial packages
4. Calculate total costs
5. See which items push her over budget so she can make substitution decisions

## Task Steps

### 1. Initial Assessment
- Examine the partially completed renovation materials spreadsheet
- Identify columns and note that some cells are empty (waste factors missing)
- Units are inconsistent (decimal ft, cm)

### 2. Standardize Measurements (Column I: "Area Sq Ft")
- Create formulas to convert all measurements to square feet
- For "decimal ft": multiply length × width directly
- For "cm": convert cm to feet (divide by 30.48), then multiply length × width
- Apply formulas to all 6 material rows

### 3. Input Missing Waste Factors (Column E)
- Fill in blank waste factor cells with appropriate percentages:
  - Floor tile: 10-15%
  - Tile adhesive: 10%
  - Waterproof membrane: 10-15%

### 4. Calculate Adjusted Quantity (Column J: "Adjusted Sq Ft")
- Create formula: Area Sq Ft × (1 + Waste Factor % / 100)
- This represents the actual amount to purchase including waste

### 5. Calculate Packages Needed (Column K)
- Create formula: ROUNDUP(Adjusted Sq Ft / Coverage per Package, 0)
- This rounds UP to nearest whole number (can't buy 0.3 of a box)

### 6. Calculate Total Cost (Column L)
- Create formula: Packages Needed × Price per Package
- Format as currency

### 7. Flag Budget Overruns (Column M: "Budget Status")
- Create IF formula: IF(Total Cost > Budget Limit, "OVER BUDGET", "OK")
- This helps identify which items to reconsider

### 8. Calculate Grand Total
- Sum the "Total Cost" column
- Display in a cell below the data (row 9-10)

### 9. Automatic Export
- The post-task hook will automatically save the completed spreadsheet

## Verification Strategy

### Verification Approach
The verifier uses **mathematical validation** of multi-step calculation chains with tolerance for minor rounding variations.

### Verification Checklist
- ✅ **Area Calculations Correct:** All measurements converted to sq ft accurately (5/6 items minimum)
- ✅ **Waste Factors Filled:** Missing waste factors filled with appropriate values (5-20% range)
- ✅ **Adjusted Quantities:** Waste factor applied correctly to calculate adjusted quantities (5/6 minimum)
- ✅ **Package Rounding:** ROUNDUP function used, packages calculated correctly (5/6 minimum)
- ✅ **Total Costs:** Costs calculated as packages × price (5/6 minimum)
- ✅ **Budget Flags:** Items over budget correctly flagged (5/6 minimum)
- ✅ **Grand Total:** Sum of all material costs calculated (within $1 tolerance)

### Scoring System
- **100%:** All 7 criteria met with accurate calculations throughout
- **75-99%:** 6/7 criteria met (one area with minor issues)
- **50-74%:** 5/7 criteria met (multiple minor issues)
- **0-49%:** <5 criteria met (fundamental formula errors)

**Pass Threshold:** 75% (requires at least 6 out of 7 criteria)

## Expected Data

| Item | Length | Width | Unit | Waste % | Coverage | Price | Budget |
|------|--------|-------|------|---------|----------|-------|--------|
| Floor Tile | 5.25 | 4.67 | decimal ft | (blank) | 12 sq ft | $42.99 | $500 |
| Wall Tile | 8.5 | 6.25 | decimal ft | 10 | 11 sq ft | $38.50 | $400 |
| Membrane | 160 | 142 | cm | (blank) | 107.64 sq ft | $89.99 | $200 |
| Paint | 8 | 6 | decimal ft | 5 | 350 sq ft | $31.99 | $100 |
| Adhesive | 5.25 | 4.75 | decimal ft | (blank) | 50 sq ft | $28.50 | $150 |
| Grout | 5.25 | 4.75 | decimal ft | 10 | 100 sq ft | $19.99 | $150 |

## Sample Expected Calculations

**Floor Tile Example:**
1. Area: 5.25 ft × 4.67 ft = 24.52 sq ft
2. Waste factor: Fill in 15%
3. Adjusted: 24.52 × 1.15 = 28.20 sq ft
4. Packages: ROUNDUP(28.20 / 12, 0) = 3 boxes
5. Cost: 3 × $42.99 = $128.97
6. Status: $128.97 < $500 → "OK"

**Waterproof Membrane Example:**
1. Area: (160/30.48) ft × (142/30.48) ft = 24.53 sq ft
2. Waste factor: Fill in 10%
3. Adjusted: 24.53 × 1.10 = 26.98 sq ft
4. Packages: ROUNDUP(26.98 / 107.64, 0) = 1 roll
5. Cost: 1 × $89.99 = $89.99
6. Status: $89.99 < $200 → "OK"

## Tips

- **Unit Conversion:** 1 cm = 1/30.48 feet (since 1 foot = 30.48 cm)
- **Waste Factors:** Typical construction waste is 10-15% for most materials
- **ROUNDUP is Critical:** Using ROUND instead of ROUNDUP would under-purchase materials
- **Formula Copying:** Create formulas in first row, then copy down to other rows
- **Budget Flags:** Help prioritize which items to reconsider if over total budget

## Technical Implementation

### Files Structure