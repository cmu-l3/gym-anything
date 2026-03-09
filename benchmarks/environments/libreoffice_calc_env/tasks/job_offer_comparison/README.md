# Job Offer Comparison Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, formula creation, date calculations, salary conversion  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Clean up messy job search tracking data and create a structured comparison of competing job offers with complex compensation packages. This task tests data standardization, multi-step calculations, and practical decision-support spreadsheet skills.

## Task Description

You're managing a job search and need to make an urgent decision between two competing offers. Your tracking spreadsheet has inconsistent formatting and you need to:

1. Standardize salary data (convert hourly rates to annual equivalents)
2. Calculate total compensation for each offer (base + bonus + benefits)
3. Calculate days since application for follow-up tracking
4. Create a clear comparison to support your decision

## Starting State

- LibreOffice Calc opens with job tracking spreadsheet
- Data contains 10+ job applications in various stages
- Mixed salary formats: some hourly ("$28/hr"), some annual ("75000")
- Inconsistent date formats
- Two offers need comparison: Company A (TechStart Inc) and Company B (DataCorp)

## Required Actions

### 1. Standardize Salary Data
- Identify hourly rates (look for "/hr" or "/hour")
- Convert to annual: hourly_rate × 2080 hours/year
- Example: $28/hr → $58,240/year
- Apply currency formatting

### 2. Calculate Total Compensation
- **Company A (TechStart Inc):**
  - Base: $75,000
  - Signing Bonus: $5,000
  - Benefits estimate: ~$8,000
  - Total: $88,000
  
- **Company B (DataCorp):**
  - Base: $82,000
  - Annual Bonus: 10% ($8,200)
  - Benefits estimate: ~$6,000
  - Total: $96,200

### 3. Track Follow-up Needs
- Calculate days since application: `=TODAY() - [Applied_Date]`
- Identify applications >14 days old (no response = need follow-up)

## Expected Results

- **Salary Conversion:** At least 2 hourly rates converted to annual
- **Company A Total Comp:** $88,000 (±$1,500)
- **Company B Total Comp:** $96,200 (±$1,500)
- **Days Since Formula:** Present in multiple cells
- **Currency Formatting:** Applied to salary columns
- **Clear Comparison:** Both totals visible in dedicated section

## Verification Criteria

1. ✅ **Salary Conversion Correct** (at least 2 hourly→annual conversions)
2. ✅ **Company A Total Compensation** ($88,000 ±$1,500)
3. ✅ **Company B Total Compensation** ($96,200 ±$1,500)
4. ✅ **Days Since Formula** (uses TODAY() function)
5. ✅ **Currency Formatting** ($ symbol applied)
6. ✅ **Comparison Structure** (both totals clearly displayed)

**Pass Threshold**: 75% (5/6 criteria must pass)

## Skills Tested

- Data cleaning and standardization
- Formula creation (TODAY(), arithmetic)
- Salary conversion logic (hourly × 2080)
- Multi-component calculations (sum of base + bonus + benefits)
- Date arithmetic
- Currency formatting
- Decision-support data structure

## Tips

- **Hourly to Annual:** Multiply by 2,080 (40 hours/week × 52 weeks)
- **Percentage Bonus:** If "10% bonus", calculate as base_salary × 0.10
- **Benefits Estimates:** 
  - "Good healthcare" ≈ $8,000/year
  - "Basic benefits" ≈ $6,000/year
- **Days Since:** Use `=TODAY()-A2` where A2 is applied date
- **Currency Format:** Select cells → Ctrl+1 → Currency → OK
- **Create comparison section:** Use new rows/columns for clear visibility

## Real-World Context

This simulates a time-sensitive career decision:
- Multiple applications tracked informally over weeks
- Data entry was rushed and inconsistent
- Two offers with different compensation structures
- Need quick, clear comparison to decide within 48-72 hours
- Other applications need follow-up tracking