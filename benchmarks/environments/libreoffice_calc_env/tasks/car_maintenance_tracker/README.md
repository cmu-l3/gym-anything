# Car Maintenance Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, conditional formatting, data completion, calculation  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~50

## Objective

Analyze a car maintenance log from a used car's previous owner to calculate upcoming service needs, identify overdue maintenance items, and budget for expenses. The spreadsheet contains incomplete data that must be filled, formulas that must be created, and conditional formatting that must be applied to quickly identify critical service needs.

## Real-World Context

**Scenario**: You just purchased a used 2019 Honda Civic with 47,500 miles on the odometer. The previous owner provided a partially completed maintenance log, but it's missing data and has no analysis of what services are due next. You're concerned about:

- **Overdue services** that could damage your engine or compromise safety
- **Upcoming expenses** you need to budget for
- **Service priority** - what needs attention immediately vs. what can wait

You need to quickly transform this incomplete log into a functional tracking system before your road trip next week.

## Task Description

The agent must:

1. **Fill Missing Data**: Complete blank mileage entries using context from surrounding records
2. **Create Service Due Formulas**: Add formulas in Column E to calculate when each service is next due based on maintenance intervals
3. **Create Miles Until Formulas**: Add formulas in Column F to calculate how many miles until each service is needed
4. **Apply Conditional Formatting**: Highlight overdue (red), due soon (yellow), and not due (green) services
5. **Calculate Total Cost**: Add a SUM formula to compute total maintenance expenses

## Data Structure

### Current State (Incomplete)

| Current Mileage: | 47500 |                        |      |                        |                          |
|------------------|-------|------------------------|------|------------------------|--------------------------|
| Date             | Service Type      | Mileage at Service | Cost | Next Service Due At | Miles Until Next Service |
| 2022-03-15       | Oil Change        | 25000              | $45  | (empty)             | (empty)                  |
| 2022-06-20       | Tire Rotation     | 27500              | $30  | (empty)             | (empty)                  |
| 2022-09-10       | Oil Change        | 30000              | $45  | (empty)             | (empty)                  |
| 2022-11-05       | Brake Inspection  | 32000              | $120 | (empty)             | (empty)                  |
| 2023-02-14       | Oil Change        | **(MISSING)**      | $45  | (empty)             | (empty)                  |
| 2023-05-30       | Tire Rotation     | 40000              | $35  | (empty)             | (empty)                  |
| 2023-08-22       | Oil Change        | 42500              | $50  | (empty)             | (empty)                  |
| 2023-11-15       | Air Filter        | 45000              | $25  | (empty)             | (empty)                  |
| 2024-01-10       | Oil Change        | 47000              | $50  | (empty)             | (empty)                  |

### Maintenance Intervals (Standard Guidelines)

- **Oil Change**: Every 5,000 miles
- **Tire Rotation**: Every 7,500 miles
- **Brake Inspection**: Every 15,000 miles
- **Air Filter**: Every 20,000 miles

## Expected Results

### Column E: Next Service Due At (Formulas)

Each cell should contain a formula like:
- For Oil Change: `=C4+5000` or `=IF(B4="Oil Change", C4+5000, ...)`
- For Tire Rotation: `=C5+7500`
- Or use a single IF formula that checks service type

### Column F: Miles Until Next Service (Formulas)

Each cell should contain: `=E4-$B$1` (Next Due - Current Mileage)

**Example Results**:
- Oil Change at 42,500 miles → Next due: 47,500 → Miles until: **0** (due now!) → **RED**
- Oil Change at 47,000 miles → Next due: 52,000 → Miles until: **4,500** → **GREEN**
- Tire Rotation at 40,000 miles → Next due: 47,500 → Miles until: **0** (due now!) → **RED**

### Conditional Formatting (Column F)

- **Red background**: Values < 0 (overdue services)
- **Yellow background**: Values 0-1000 (due soon)
- **Green background**: Values > 1000 (not due yet)

### Total Cost

A cell containing: `=SUM(D4:D13)` → Result: **$480**

## Verification Criteria

1. ✅ **Column E Formulas**: At least 60% of data rows contain formulas (not hardcoded values)
2. ✅ **Column F Formulas**: At least 60% of data rows contain formulas referencing Column E and B1
3. ✅ **Conditional Formatting**: Formatting rules detected on Column F
4. ✅ **Calculations Accurate**: Spot-check of 3 rows shows correct "Next Due" values (±1 mile tolerance)
5. ✅ **Missing Data Filled**: Cell C8 (Feb 2023 Oil Change) contains a reasonable mileage value (32,000-38,000)
6. ✅ **Total Cost Calculated**: SUM formula present with correct total ($480 ±$10)
7. ✅ **Overdue Items Identified**: At least 1 service shows negative "Miles Until" value

**Pass Threshold**: 70% (5 out of 7 criteria must pass)

## Skills Tested

### Formula Skills
- Arithmetic formulas (addition, subtraction)
- Absolute cell references (`$B$1`)
- IF statements for conditional logic (advanced)
- SUM function for totals

### Formatting Skills
- Conditional formatting dialog navigation
- Rule creation based on cell values
- Color application for visual indicators

### Data Skills
- Logical reasoning to fill missing values
- Understanding maintenance interval patterns
- Spotting overdue vs. upcoming services

### Practical Skills
- Real-world automotive maintenance knowledge
- Urgency assessment (safety-critical vs. routine)
- Budget planning and expense tracking

## Setup

The setup script:
- Creates `car_maintenance_log.csv` with incomplete data
- Converts to ODS format for better formula support
- Launches LibreOffice Calc with the maintenance log
- Positions cursor at the start of the data

## Export

The export script:
- Saves the modified file as `car_maintenance_analyzed.ods`
- Closes LibreOffice Calc
- Preserves all formulas and formatting

## Verification

The verifier performs comprehensive checks:

1. **Formula Detection**: Parses ODS file to verify formulas (not just values) exist in Columns E and F
2. **Conditional Formatting**: Analyzes ODS XML to detect formatting rules
3. **Calculation Validation**: Spot-checks specific rows for correct Next Due and Miles Until calculations
4. **Data Completeness**: Verifies missing mileage (row 8) was filled with reasonable value
5. **Total Cost**: Validates SUM formula and checks result equals expected total
6. **Overdue Detection**: Confirms at least one service shows as overdue (negative miles)

### Verification Robustness

The verifier is designed to handle:
- Different formula syntaxes (simple arithmetic vs. complex IF statements)
- Various file save locations (analyzed.ods, log.ods, or CSV)
- Partial completions (partial credit for some criteria)
- Edge cases like rounding differences (±1 mile tolerance)
- Multiple possible cell locations for total cost

## Tips for Agents

1. **Start with missing data**: Fill C8 first to have complete data for formulas
2. **Use helper columns**: Can create interim calculations if needed
3. **Test one formula first**: Create formula in E4, verify it works, then copy down
4. **Absolute references**: Use `$B$1` for current mileage so it doesn't change when copying
5. **Conditional formatting wizard**: Format → Conditional Formatting → Condition...
6. **Check your work**: Look for negative values in Column F - those are overdue!

## Why This Task Matters

This task simulates a common real-world challenge: inheriting incomplete data and needing to quickly make it actionable. Skills learned here apply to:

- **Personal finance**: Tracking expenses, budgeting
- **Home maintenance**: HVAC filter changes, appliance servicing  
- **Health tracking**: Medication schedules, appointment reminders
- **Asset management**: Equipment maintenance, warranty tracking

The combination of data cleanup, formula logic, and visual highlighting represents practical spreadsheet workflows used daily by millions of people managing their lives and businesses.