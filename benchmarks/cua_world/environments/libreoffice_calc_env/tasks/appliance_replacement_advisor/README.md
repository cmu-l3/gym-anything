# Home Appliance Replacement Advisor Task

**Difficulty**: 🟡 Medium  
**Skills**: Date arithmetic, conditional logic, financial analysis, decision support  
**Duration**: 180 seconds (3 minutes)  
**Steps**: ~15

## Objective

Perform lifecycle cost analysis for home appliances by calculating age, age percentages, repair recommendations, energy costs, and replacement priorities. This task simulates a real homeowner's dilemma: deciding which aging appliances to repair versus replace based on multiple economic factors.

## Scenario

Sarah is a homeowner whose 12-year-old refrigerator just broke down with a $450 repair quote. She needs a systematic way to analyze all her major appliances to determine which ones are approaching end-of-life and should be prioritized for replacement. She has created an inventory but needs help with the analysis.

## Starting State

- LibreOffice Calc opens with appliance inventory data
- Columns provided:
  - Appliance name
  - Purchase Date
  - Expected Lifespan (years)
  - Last Repair Cost
  - Current Repair Quote
  - Energy Use (kWh/year)
  - Replacement Cost
- Electricity rate: $0.12/kWh (provided in spreadsheet)

## Required Actions

### 1. Calculate Current Age (Required)
- Create "Age (Years)" column
- Formula: `=YEAR(TODAY())-YEAR(PurchaseDate)` or `=DATEDIF(PurchaseDate,TODAY(),"Y")`
- Apply to all appliances

### 2. Calculate Age Percentage (Required)
- Create "Age % of Lifespan" column
- Formula: `=(Age/ExpectedLifespan)*100`
- Format as percentage

### 3. Create Replacement Priority Flags (Required)
- Create "Replacement Priority" column
- Use IF logic: `=IF(AgePercent>=80,"HIGH",IF(AgePercent>=60,"MEDIUM","LOW"))`
- This flags aging appliances for attention

### 4. Apply 50% Repair Rule (Required)
- Create "Repair Recommended?" column
- Industry standard: Don't repair if cost > 50% of replacement
- Formula: `=IF(CurrentRepairQuote/ReplacementCost>0.5,"NO - REPLACE","YES - REPAIR")`

### 5. Calculate Annual Energy Cost (Optional but recommended)
- Create "Annual Energy Cost" column
- Formula: `=EnergyUse*$ElectricityRate$` (using absolute reference)

### 6. Prioritization (Optional but recommended)
- Sort data by Age % or create Urgency Score
- Higher scores/percentages = more urgent replacement need

## Success Criteria

1. ✅ **Age Calculated**: Age column with date formulas (not hardcoded)
2. ✅ **Age Percentage**: Calculated as (Age/Lifespan)*100
3. ✅ **Priority Logic**: IF statements assign HIGH/MEDIUM/LOW based on thresholds
4. ✅ **50% Repair Rule**: Repair recommendations based on cost ratio
5. ✅ **Energy Costs**: Annual costs calculated with proper cell references
6. ✅ **Formulas Present**: Calculated columns use formulas (not manual entry)
7. ✅ **Sorted or Scored**: Data sorted by urgency or urgency score created
8. ✅ **Visual Formatting**: Evidence of conditional formatting or highlighting

**Pass Threshold**: 75% (6/8 criteria must pass)

## Skills Tested

- Date arithmetic functions (TODAY, YEAR, DATEDIF)
- Percentage calculations
- Nested IF conditional logic
- Cost-benefit analysis formulas
- Absolute vs relative cell references
- Data sorting
- Conditional formatting (optional)
- Multi-criteria decision support

## Tips

- Use TODAY() function for current date calculations
- Remember to use $ for absolute references (electricity rate)
- IF statements can be nested for multiple conditions
- Sort data: Data → Sort menu
- Conditional formatting: Format → Conditional Formatting
- Industry "50% rule": If repair costs exceed 50% of replacement cost, replace instead

## Real-World Application

This task mirrors actual home maintenance decisions where owners must balance:
- Appliance age and remaining lifespan
- Repair costs vs replacement costs
- Energy efficiency improvements in newer models
- Budget prioritization across multiple needs