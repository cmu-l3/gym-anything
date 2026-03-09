# Tip Pool Distribution Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, policy interpretation, proportional distribution, multi-role calculation  
**Duration**: 300 seconds  
**Steps**: ~20

## Objective

Calculate fair tip distribution for restaurant staff using a tip pooling system. Apply the restaurant's policy (percentage-based splits between service and support staff), calculate proportional distributions based on hours worked, and handle staff working multiple roles.

## Task Description

**Context**: You're a shift manager at "The Golden Spoon" restaurant. The previous manager quit abruptly mid-week, leaving the tip pooling spreadsheet incomplete. Payroll processes tomorrow (Friday), and staff are waiting for their tip amounts. You need to complete the calculations before your shift ends.

**The agent must:**
1. Review the incomplete tip pooling spreadsheet
2. Understand the restaurant's tip pooling policy (stated in spreadsheet)
3. Calculate support staff tip pool (20% of total tips = $570)
4. Calculate service staff tip pool (80% of total tips = $2,280)
5. Sum total hours for each role category
6. Calculate hourly tip rate for each category
7. Calculate individual tip amounts proportional to hours worked
8. Handle multi-role staff (one person worked as both server and busser)
9. Verify total distributed tips equal $2,850

## Tip Pooling Policy

- **Total tips collected:** $2,850.00
- **Support Staff (bussers, food runners):** 20% of total = $570.00
- **Service Staff (servers, bartenders):** 80% of total = $2,280.00
- **Distribution:** Proportional to hours worked within each role
- **Multi-role staff:** Hours counted separately for each role

## Expected Results

- Support staff pool: $570.00
- Service staff pool: $2,280.00
- Support hourly rate: $570 / total_support_hours
- Service hourly rate: $2,280 / total_service_hours
- Individual tips = hours × hourly_rate (for their role)
- Multi-role staff get sum of both calculations
- **Total of all tips must equal $2,850.00**

## Verification Criteria

1. ✅ **Policy Split Correct**: Support pool = $570, Service pool = $2,280 (±$1)
2. ✅ **Total Reconciliation**: Sum of individual tips = $2,850 (±$1)
3. ✅ **Formulas Present**: At least 70% of calculation cells use formulas
4. ✅ **Hours Calculated**: Total hours for each role correctly summed
5. ✅ **Proportional Distribution**: Individual tips match expected proportions (±$2)
6. ✅ **No Errors**: No #DIV/0!, #REF!, #VALUE! errors

**Pass Threshold**: 85% (requires correct policy and accurate math)

## Skills Tested

- Formula creation (SUM, multiplication, division)
- Cell references (absolute and relative)
- Policy interpretation
- Proportional distribution calculation
- Multi-role handling
- Data validation
- Quality control

## Setup

The setup script:
- Creates incomplete tip pooling spreadsheet with:
  - Staff names, roles, and hours worked
  - Tip pooling policy clearly stated
  - Empty cells for calculations
  - One multi-role staff member (edge case)
- Launches LibreOffice Calc with the spreadsheet
- Positions cursor at first calculation cell

## Export

The export script:
- Saves the file as `/home/ga/Documents/tip_distribution.ods`
- Closes LibreOffice Calc

## Verification

Verifier parses ODS file and validates:
1. Policy split accuracy (20/80 split applied correctly)
2. Mathematical reconciliation (total equals $2,850)
3. Formula presence (not just hard-coded values)
4. Hours summation correctness
5. Proportional distribution accuracy
6. No calculation errors

## Tips

- Use SUM() to total hours for each role category
- Calculate hourly rate as: pool_amount / total_hours
- Individual tip = hours × hourly_rate
- For multi-role staff (Maria): calculate both portions separately, then sum
- Verify your total equals $2,850 before finishing
- Use formulas, not hard-coded values, for full credit