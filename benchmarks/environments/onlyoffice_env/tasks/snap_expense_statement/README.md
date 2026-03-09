# SNAP Expense Statement Task (`snap_expense_statement@1`)

## Overview

This task challenges an agent to create a properly formatted SNAP (Supplemental Nutrition Assistance Program) benefit recertification expense statement from fragmented household expense data. The agent must consolidate information from a messy text file, organize it into state-required categories, create proper SUM formulas, and format the spreadsheet for official submission.

## Real-World Context

**Scenario:** Maria, a single mother receiving SNAP benefits, needs to submit a recertification expense statement within 10 days. She has disorganized notes about her monthly expenses but struggles with spreadsheet software. The task simulates helping her create a properly formatted document that meets government requirements.

**Stakes:** Improperly formatted or incomplete expense statements can delay or suspend benefits, creating immediate hardship for vulnerable families.

## Task Requirements

### Input
- **expense_notes.txt**: Disorganized text notes containing expense information (rent, utilities, childcare, medical costs, phone bill)

### Output
- **SNAP_Expense_Statement.xlsx**: Properly formatted spreadsheet with:
  - Title and household information
  - Column headers for categories and amounts
  - Expense categories: Housing, Electric, Gas, Water, Childcare, Medical, Phone (optional)
  - Amounts extracted from notes
  - **SUM formula** for total (not manually calculated)
  - Currency formatting applied

## Key Skills Tested

1. **Data Consolidation**: Extract structured data from unstructured text
2. **Spreadsheet Organization**: Create proper headers and categories
3. **Formula Competency**: Use =SUM() instead of manual calculation
4. **Attention to Detail**: Accurately transfer all expense amounts
5. **Category Judgment**: Correctly classify expenses (e.g., recognizing medical includes prescriptions + copays)
6. **Formatting**: Apply currency format and proper alignment

## Verification Criteria

The verifier checks **5 major criteria** (20% each):

### 1. Structural Integrity (20%)
- ✅ Title mentions "SNAP" or "Expense Statement"
- ✅ Column headers present ("Expense Category", "Monthly Amount")
- ✅ Organized row structure

### 2. Formula Validation (20%)
- ✅ Total row contains **=SUM(...)** formula
- ❌ Hard-coded numbers in total row = only partial credit
- ✅ Formula syntax is valid

### 3. Data Accuracy (20%)
- ✅ Housing: $875 (±$2 tolerance)
- ✅ Electric: $67 (accepts $67-$67.23)
- ✅ Gas: $43
- ✅ Water: $29
- ✅ Childcare: $200
- ✅ Medical: $85 (inhaler $35 + diabetes meds $50)
- ⚠️ Phone: $45 (optional, not penalized if excluded)

### 4. Completeness (20%)
- ✅ All 6 required categories present (Housing, Electric, Gas, Water, Childcare, Medical)
- ⚠️ Phone is optional

### 5. Total Correctness (20%)
- ✅ Formula produces correct sum ($1,299 without phone or $1,344 with phone)
- ✅ Total is within ±$5 of expected value

**Pass Threshold:** 80/100 points (requires 4/5 criteria or equivalent)

## Expected Expense Values

From the expense notes:

| Category | Amount | Notes |
|----------|--------|-------|
| Housing (Rent) | $875 | Lease with Valley Vista Apartments |
| Electric | $67 | APS account (accepts $67-$67.23) |
| Gas/Heating | $43 | Southwest Gas |
| Water/Sewer | $29 | Quarterly bill $87 ÷ 3 |
| Childcare | $200 | Sister Maria watches kids |
| Medical | $85 | Jamie's inhaler $35 + diabetes meds $50 |
| Phone | $45 | Prepaid Cricket (optional) |
| **TOTAL** | **$1,299-$1,344** | Depending on phone inclusion |

## Common Pitfalls

1. **Hard-coding the total**: Typing "1299" instead of "=SUM(B5:B11)"
2. **Missing medical calculation**: Not adding $35 + $50 = $85
3. **Wrong categories**: Using "Utilities" instead of separate Electric/Gas/Water
4. **Incomplete data**: Forgetting to include childcare or medical
5. **No formatting**: Not applying currency format ($875.00)

## Difficulty Justification

**Why Medium Difficulty:**
- Requires working across two applications (notes viewer + spreadsheet)
- Must parse unstructured text to extract amounts
- Requires formula knowledge (=SUM syntax)
- Tests categorization judgment
- Multiple data entry points with potential for errors

**Not Too Hard:**
- All information is provided in notes file
- Only basic SUM formula needed (no complex functions)
- Standard spreadsheet structure (rows and columns)
- Clear category names in notes
- No conditional logic required

## Files
