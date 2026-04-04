# Insurance Plan Comparison Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, conditional logic, scenario analysis, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Help a frustrated user compare health insurance plans during open enrollment by calculating total annual costs under different usage scenarios and identifying the most cost-effective option. This simulates a high-stakes real-world decision millions face annually.

## Task Description

The agent must:
1. Review 3 insurance plans (Bronze, Silver, Gold) with their parameters (monthly premium, deductible, coinsurance rate, out-of-pocket max)
2. Calculate total annual premium costs for each plan (monthly × 12)
3. Build formulas to calculate total annual costs under 3 healthcare usage scenarios:
   - **Low Use**: $2,000 in medical costs
   - **Medium Use**: $8,000 in medical costs  
   - **High Use**: $25,000 in medical costs
4. Apply proper cost calculation logic considering deductibles, coinsurance, and OOP max caps
5. Use conditional formatting to highlight the best (lowest cost) plan for each scenario
6. Save the completed analysis

## Starting State

A spreadsheet opens with:
- **Plan parameters** (rows 2-4): Bronze, Silver, Gold plans
- **Columns**: Plan Name, Monthly Premium, Annual Deductible, Coinsurance Rate (%), OOP Max
- **Scenario columns** to be filled: Annual Premium, Low Use Total Cost, Medium Use Total Cost, High Use Total Cost
- **Assumed medical costs**: $2,000, $8,000, $25,000 noted in headers

## Insurance Cost Calculation Logic

For each scenario: