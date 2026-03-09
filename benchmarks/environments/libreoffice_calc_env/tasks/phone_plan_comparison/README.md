# Family Phone Plan Cost Comparison Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-component calculations, conditional logic (IF statements), MIN function, formula composition  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Help a family compare cell phone plan costs across three carriers with complex pricing structures. Calculate total monthly costs for each carrier option, identify the most cost-effective plan, and determine potential savings. This task tests multi-step formula creation, conditional logic, and practical decision-making skills.

## Scenario

A family of 4 is currently paying $180/month for their cell phone plan, but their promotional rate is expiring next month and the cost will jump to $240/month. They need to compare three carrier options to find the cheapest plan. The family uses a total of 22 GB of data per month.

## Task Description

The agent must:
1. Open the provided spreadsheet with family usage data and carrier pricing
2. Calculate total monthly cost for **Carrier A** (MegaTel) in cell **B14**
3. Calculate total monthly cost for **Carrier B** (ConnectPlus) in cell **B15** with overage logic
4. Calculate total monthly cost for **Carrier C** (FamilyLink) in cell **B16**
5. Find the best (lowest) plan cost in cell **B18** using MIN function
6. Calculate monthly savings vs. current plan in cell **B19**
7. Save the file

## Carrier Pricing Details

### Carrier A (MegaTel)
- Base fee: $85/month
- Per-line fee: $20/line
- Data plan: $30/month (includes 25GB)
- Family uses 22GB, so no overage

**Formula for B14:** `=85 + (20 * 4) + 30`  
**Expected result:** $195.00

### Carrier B (ConnectPlus)
- Base fee: $60/month
- Per-line fee: $25/line
- Data included: 20GB
- Overage fee: $15/GB over 20GB
- Family uses 22GB, so 2GB overage

**Formula for B15:** `=60 + (25 * 4) + IF(22 > 20, (22 - 20) * 15, 0)`  
**Expected result:** $190.00

### Carrier C (FamilyLink)
- Base fee: $100/month
- Per-line fee: $15/line
- Data: Unlimited (no overage charges)

**Formula for C16:** `=100 + (15 * 4) + 0`  
**Expected result:** $160.00

### Best Plan & Savings
**Formula for B18:** `=MIN(B14:B16)`  
**Expected result:** $160.00

**Formula for B19:** `=240 - B18`  
**Expected result:** $80.00

## Verification Criteria

1. ✅ **Carrier A Formula Valid:** Correct calculation structure and result ($195)
2. ✅ **Carrier B Formula Valid:** IF statement correctly handles overage ($190)
3. ✅ **Carrier C Formula Valid:** Correct calculation structure and result ($160)
4. ✅ **Best Plan Identified:** MIN function finds lowest cost ($160)
5. ✅ **Savings Calculated:** Correct formula and result ($80)

**Pass Threshold**: 75% (requires at least 4 out of 5 criteria)

## Skills Tested

- Multi-component cost calculations (base + variable fees)
- Conditional logic (IF statements for usage thresholds)
- Cell references (relative and absolute)
- MIN function for comparison
- Formula composition (combining multiple operations)
- Practical financial decision-making

## Spreadsheet Layout
