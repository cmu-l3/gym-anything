# LibreOffice Calc Formula Debugging Task (`formula_archaeology@1`)

## Overview

This task challenges an agent to **reverse-engineer and repair** a broken expense tracking spreadsheet inherited from a departed colleague. The agent must identify formula errors (#REF!, incorrect ranges), understand the intended calculation logic, and fix formulas to produce correct results. This represents a critical real-world skill: debugging inherited spreadsheets where documentation is absent and formulas are cryptic.

## Rationale

**Why this task is valuable:**
- **Real-World Urgency:** Extremely common scenario when employees leave, systems change, or files are shared
- **Diagnostic Skills:** Tests ability to identify WHY calculations are wrong, not just WHAT is wrong
- **Formula Comprehension:** Requires understanding existing logic rather than creating from scratch
- **Error Recognition:** Must identify #REF! errors, broken range references, and logical mistakes
- **Practical Problem-Solving:** Mirrors actual work situations where "it used to work but now it doesn't"
- **Reverse Engineering:** Tests ability to infer intent from partial/broken implementations
- **Business Context:** Expense tracking is universal—every organization does this

**Skill Progression:** This represents **intermediate-to-advanced** difficulty, requiring formula literacy, debugging skills, and logical reasoning about data relationships.

## Scenario & Context

**The Situation:**
You're a small business owner. Your bookkeeper quit suddenly, leaving behind an expense tracking spreadsheet for managing monthly business expenses. The sheet calculates category totals and flags over-budget spending. However, after adding new expense entries for this month, several formulas broke and show errors. You need to fix it urgently for tomorrow's financial review meeting.

**What went wrong:**
- New expense rows were added, but SUM ranges don't include them
- A column was deleted, breaking formulas that referenced it
- Some formulas have incorrect cell references
- Budget variance calculations are wrong

**Your goal:**
Fix all broken formulas so the spreadsheet correctly calculates:
1. Total expenses by category (Office Supplies, Travel, Utilities, Marketing)
2. Budget variance (actual spending minus budget)
3. Over-budget warnings (flag categories exceeding budget)

## Task Steps

### 1. Initial Assessment
- Open the pre-populated expense tracking spreadsheet
- Observe the layout: expense entries in rows, categories in columns, totals and budgets
- Identify cells showing #REF! errors
- Note totals that seem obviously wrong

### 2. Inspect Category Total Formulas
- Click on category total cells
- Examine formulas in the formula bar
- Identify problems: ranges too small, #REF! errors, wrong column references

### 3. Fix Category Totals
- Edit SUM formulas to include all expense rows for each category
- Ensure ranges cover all data rows
- Verify totals now show reasonable values

### 4. Inspect Budget Variance Formulas
- Navigate to "Budget Variance" row
- Identify formula errors: wrong cell references, #REF! errors

### 5. Fix Budget Variance Calculations
- Correct formulas to subtract Budget from Actual
- Ensure formula logic is consistent across all categories

### 6. Inspect Over-Budget Warning Formulas
- Find cells that should show "OVER BUDGET" warnings
- These use IF functions
- Identify broken references or incorrect logic

### 7. Fix Warning Formulas
- Correct IF formulas to reference the right variance cells
- Ensure logic is correct (variance > 0 means over budget)

### 8. Verify All Fixes
- Review all corrected formulas
- Check that totals, variances, and warnings all show sensible values
- Ensure no #REF! errors remain

## Verification Criteria

- ✅ **No Formula Errors:** Zero #REF! errors in spreadsheet
- ✅ **Correct Category Totals:** All category totals match expected sums
- ✅ **Accurate Variances:** Budget variance = (Actual - Budget) for all categories
- ✅ **Valid Warnings:** Over-budget flags appear correctly
- ✅ **Complete Data Coverage:** All expense rows included in calculations
- ✅ **Consistent Formula Patterns:** Similar formulas across categories

**Pass Threshold**: 85% (requires correct fixes with at most minor issues)

## Expected Results

**Category Totals (Row 18):**
- Office Supplies: $450
- Travel: $1,250
- Utilities: $320
- Marketing: $890

**Budget Variances (Row 24):**
- Office Supplies: -$50 (under budget)
- Travel: +$150 (over budget)
- Utilities: -$80 (under budget)
- Marketing: +$90 (over budget)

**Status Warnings (Row 27):**
- Office Supplies: "OK"
- Travel: "OVER BUDGET"
- Utilities: "OK"
- Marketing: "OVER BUDGET"