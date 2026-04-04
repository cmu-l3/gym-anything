# Tool Library Damage Investigation Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, date manipulation, logical inference, financial calculations, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Investigate a tool library damage incident by cleaning messy borrowing data, standardizing inconsistent date formats, calculating possession periods with missing information, and determining financial responsibility. Work with real-world messy CSV data to solve a community dispute about a broken pressure washer.

## Scenario

You're the frustrated coordinator of a neighborhood tool library (8 neighbors sharing expensive tools). A pressure washer was returned broken—repair costs **$85**. The borrowing log is a disaster: mixed date formats, missing return dates, and conflicting information. Sarah swears she returned it fine, Mike denies borrowing it (but it's logged), and everyone's angry. 

**Your mission**: Figure out who had possession during the damage period (May 15-20, 2024) and split the repair cost fairly.

## Starting State

- CSV file (`tool_library_log.csv`) with messy borrowing records
- Multiple date formats: "5/3/24", "May 15, 2024", "2024-05-18", "5-22-2024"
- Missing return dates for some entries
- Conflicting information about Mike's borrowing
- Damage period: **May 15-20, 2024**
- Repair cost: **$85.00**

## Required Actions

### 1. Data Standardization
- Import the CSV into LibreOffice Calc
- Create new columns for standardized dates
- Convert all date formats to consistent DATE type (e.g., YYYY-MM-DD or use DATE function)

### 2. Missing Data Inference
- Identify rows with missing return dates
- Infer probable return dates:
  - If next person borrowed same tool → returned just before their borrow date
  - Use logical formulas: `IF(ISBLANK(return_date), next_borrow_date - 1, return_date)`

### 3. Possession Period Calculation
- Create column for days possessed: `return_date - borrow_date + 1`
- Handle edge cases (same-day returns, missing dates)

### 4. Damage Period Identification
- Create column flagging borrowers during May 15-20, 2024
- Use AND/OR logic: `IF(AND(borrow_date <= DATE(2024,5,20), return_date >= DATE(2024,5,15)), "YES", "NO")`

### 5. Cost Allocation
- Calculate days possessed during damage period
- Compute proportional responsibility: `overlap_days / total_damage_period_days × $85`
- Ensure costs sum to $85

### 6. Conditional Formatting
- Highlight rows with damage period overlap (red/orange)
- Highlight missing/inconsistent data (yellow)
- Format cost amounts as currency

### 7. Summary Section
- Total responsible borrowers
- Cost breakdown per person
- Unresolved data issues

## Success Criteria

1. ✅ **Dates Standardized**: 80%+ of dates converted to consistent format
2. ✅ **Missing Data Inferred**: Return dates logically inferred (3+ cases)
3. ✅ **Damage Period Identified**: 2-4 borrowers flagged (May 15-20)
4. ✅ **Costs Calculated**: Sum to $85 (±$0.50), proportionally allocated
5. ✅ **Conditional Formatting**: 2+ formatting rules visible
6. ✅ **Formulas Present**: Key calculations use formulas (5+ cells)

**Pass Threshold**: 70% (4 out of 6 criteria must pass)

## Skills Tested

- CSV import and parsing
- Date format recognition and conversion
- DATE/DATEVALUE/TEXT functions
- IF/AND/OR conditional logic
- Missing data inference
- Financial calculations
- Conditional formatting
- Cell references and formulas
- Data cleaning judgment

## Tips

- Use DATE() function for standardization: `DATE(2024, 5, 15)`
- DATEVALUE() can parse text dates: `DATEVALUE("May 15, 2024")`
- For inferring return dates, reference the next row's borrow date
- AND() function checks multiple conditions: `AND(date1 <= target, date2 >= target)`
- Use absolute references ($) when copying formulas
- Format → Conditional → Condition to add highlighting rules
- Sum check: All individual costs should equal $85.00

## Sample Data Structure

| Borrower | Tool | Borrow_Date | Return_Date | Notes |
|----------|------|-------------|-------------|-------|
| Sarah Miller | Pressure Washer | 5/3/24 | 5/7/2024 | Cleaned driveway |
| Mike Roberts | Pressure Washer | 5-10-2024 | | Denies borrowing |
| Jessica Lee | Pressure Washer | 2024-05-14 | May 18, 2024 | House siding |

**Expected Analysis**: Jessica Lee clearly had it during damage period. Mike's missing return date should be inferred from Jessica's borrow date (5/13 or earlier). Both may share responsibility.