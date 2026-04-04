# Streaming Service Subscription Audit Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, date functions, conditional logic, financial analysis  
**Duration**: 300 seconds  
**Steps**: ~50

## Objective

Organize and analyze streaming service subscription data to help make informed decisions about which services to keep or cancel. Work with a partially-complete spreadsheet containing subscription information with various billing cycles, shared costs, and upcoming renewals. Calculate normalized monthly costs, identify subscriptions with upcoming renewals, flag cost-shared services, and determine cost-per-hour-watched metrics.

## Task Description

The agent must:
1. Open the provided ODS file with subscription data (8 services)
2. Add new calculated columns:
   - **Monthly Cost**: Normalize annual subscriptions to monthly equivalent
   - **Days to Renewal**: Calculate days until next renewal date
   - **Renewal Alert**: Flag subscriptions renewing in ≤30 days
   - **Cost/Hour**: Calculate cost per hour watched (handle zero hours)
   - **Amount Owed**: Calculate 50% split for shared subscriptions
3. Create summary totals for monthly cost and amounts owed
4. Save the completed spreadsheet

## Starting Data Structure

| Service Name | Cost | Billing Cycle | Renewal Date | Shared With | Hours Watched/Month |
|--------------|------|---------------|--------------|-------------|---------------------|
| Netflix | 15.99 | Monthly | 2025-02-15 | | 25 |
| Disney+ | 79.99 | Annual | 2025-03-20 | | 12 |
| HBO Max | 15.99 | Monthly | 2025-01-28 | Sarah | 8 |
| ... | ... | ... | ... | ... | ... |

## Required Calculated Columns

### 1. Monthly Cost
- **Formula**: `=IF(C2="Annual", B2/12, B2)`
- **Purpose**: Convert annual subscriptions to monthly for comparison
- **Format**: Currency ($)

### 2. Days to Renewal
- **Formula**: `=D2-TODAY()`
- **Purpose**: Track how soon each subscription renews
- **Format**: Number

### 3. Renewal Alert
- **Formula**: `=IF(F2<=30, "RENEWING SOON", "")`
- **Purpose**: Highlight subscriptions renewing within 30 days
- **Format**: Text

### 4. Cost/Hour
- **Formula**: `=IF(G2=0, "Not Used", E2/G2)`
- **Purpose**: Calculate value per hour of usage
- **Format**: Currency or Text

### 5. Amount Owed
- **Formula**: `=IF(H2<>"", E2/2, 0)`
- **Purpose**: Calculate amounts owed from shared subscriptions
- **Format**: Currency ($)

### 6. Totals (Optional but recommended)
- Total Monthly Cost: `=SUM(E:E)` or `=SUM(E2:E9)`
- Total Amount Owed: `=SUM(J:J)` or `=SUM(J2:J9)`

## Success Criteria

1. ✅ **Required Columns Present**: All 5-6 calculated columns exist with correct headers
2. ✅ **Monthly Cost Normalized**: Annual subscriptions correctly converted (÷12)
3. ✅ **Renewal Alerts Working**: Subscriptions renewing in ≤30 days flagged
4. ✅ **Cost-Per-Hour Calculated**: Formula handles division by zero
5. ✅ **Total Cost Accurate**: SUM formula calculates total within tolerance
6. ✅ **Formulas Applied Consistently**: All data rows have formulas (not just first row)

**Pass Threshold**: 75% (5 out of 6 criteria must pass)

## Skills Tested

- **Formula Creation**: Writing IF, division, and date formulas
- **Date Functions**: Using TODAY() for dynamic date calculations
- **Conditional Logic**: Multi-condition IF statements
- **Error Handling**: Division by zero protection
- **Cell References**: Proper relative/absolute references
- **Data Normalization**: Converting different billing cycles to common unit
- **Financial Analysis**: Cost-effectiveness calculations

## Tips

- Start by adding column headers for the calculated fields
- Test formulas on the first data row before copying down
- Use IF statements to handle different billing cycles
- TODAY() function provides current date dynamically
- Handle division by zero with IF or IFERROR
- Copy formulas down to all data rows (rows 2-9)
- Format currency columns with $ symbol
- Save regularly with Ctrl+S

## Common Challenges

- **Date arithmetic**: Subtracting TODAY() from future date gives positive days remaining
- **String matching**: Billing cycle text must match exactly ("Annual" vs "annual")
- **Division by zero**: Must check if Hours Watched > 0 before dividing
- **Formula copying**: Ensure formulas copy to ALL rows, not just first few
- **Empty cells**: Shared With column may be blank, use `<>""` to check

## Real-World Context

This task simulates the common problem of "subscription creep" where people accumulate multiple streaming services and lose track of costs. The spreadsheet helps answer:
- How much am I really spending per month?
- Which services am I not using?
- What renewals are coming up soon?
- Who owes me money for shared subscriptions?
- Which subscriptions offer the best value per hour watched?