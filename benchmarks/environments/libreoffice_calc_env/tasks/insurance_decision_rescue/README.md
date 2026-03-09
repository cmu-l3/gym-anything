# Health Insurance Decision Rescue Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, scenario modeling, conditional formatting, decision support  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~20-25

## Objective

Help a stressed user compare confusing health insurance plan options during open enrollment. The agent must clean up messy plan data, create scenario models for different usage levels (healthy year, moderate use, high needs), calculate total annual costs, and provide decision support through conditional formatting and recommendations.

## Task Description

The agent must:
1. Examine a partially-filled spreadsheet with inconsistent insurance plan data
2. Standardize data (convert annual premiums to monthly, fill missing values from notes)
3. Create three usage scenario models (Minimal Use, Moderate Use, High Use)
4. Build formulas to calculate total annual cost for each plan under each scenario
5. Apply conditional formatting to highlight best/worst options
6. Add decision support column indicating which plan is best for different needs

## Starting State

- LibreOffice Calc opens with partially-completed insurance comparison spreadsheet
- 4 insurance plans with realistic but inconsistent data
- Some premiums listed annually, others monthly
- One plan missing out-of-pocket maximum (noted in comments)
- Empty scenario sections needing formulas

## Data Structure

### Plan Data Columns (A-H):
- Plan Name
- Monthly Premium (some need conversion from annual)
- Deductible
- Co-insurance %
- Out-of-Pocket Max (one missing, noted below)
- PCP Visit Cost
- Specialist Visit Cost
- Generic Rx Cost

### Scenario Models (to be created):
- **Scenario 1: Minimal Use** - 2 PCP visits, 1 specialist, $300 prescriptions
- **Scenario 2: Moderate Use** - 4 PCP visits, 3 specialists, $1,500 prescriptions
- **Scenario 3: High Use** - Hit deductible, reach near OOP max

## Required Actions

1. **Data Cleanup**: Convert Plan B's annual premium ($7,200/year) to monthly ($600/month)
2. **Fill Missing Data**: Add Plan C's OOP max ($8,500) from notes section
3. **Create Scenario Section**: Build three columns for scenario calculations
4. **Formula Creation**: Calculate annual cost = (Premium × 12) + estimated out-of-pocket costs
5. **Conditional Formatting**: Highlight lowest-cost plan for each scenario
6. **Decision Support**: Add "Best For" column with logic indicating optimal use cases

## Success Criteria

1. ✅ **Data Structure**: All 8 required columns present with complete data
2. ✅ **Three Scenarios**: Minimal, Moderate, High use sections with distinct parameters
3. ✅ **Formula Correctness**: Annual cost formulas verified for at least 2 plans (±$100 tolerance)
4. ✅ **Conditional Formatting**: At least 3 cells formatted to highlight min/max values
5. ✅ **Best Plan Identified**: Lowest cost plan for Scenario 1 clearly marked
6. ✅ **Decision Logic**: Formula or text indicating scenario-specific recommendations

**Pass Threshold**: 70% (requires 4-5 out of 6 criteria)

## Expected Calculations

Example for Minimal Use scenario with Plan A:
- Annual Premium: $450 × 12 = $5,400
- Medical costs: (2 × $25 PCP) + (1 × $50 specialist) + $300 Rx = $400
- Patient pays: $400 (under deductible)
- **Total Annual Cost: $5,400 + $400 = $5,800**

## Skills Tested

- Data standardization and cleanup
- Formula creation with cell references
- Nested IF statements for cost calculations
- Conditional formatting rules
- Scenario modeling
- Multi-criteria decision support
- Financial literacy (understanding insurance cost structures)

## Tips

- Read the notes section carefully for missing data
- Premium conversion: Annual ÷ 12 = Monthly
- For minimal use, most costs stay under deductible
- High use scenarios should approach or hit out-of-pocket maximum
- Use conditional formatting: Format → Conditional Formatting → Condition
- Best approach: Build one formula, then copy across plans