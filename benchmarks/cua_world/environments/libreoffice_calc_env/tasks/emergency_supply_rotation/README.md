# Emergency Supply Rotation Task

**Difficulty**: 🟡 Medium  
**Skills**: Date formulas, conditional logic, data formatting, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Organize emergency preparedness supplies by tracking expiration dates, calculating days until expiration, categorizing urgency status, and applying visual formatting for quick assessment. This task tests date arithmetic, nested IF statements, conditional formatting, and practical spreadsheet organization skills.

## Scenario

You've accumulated emergency supplies over time but haven't maintained organized records. Some items have expiration dates recorded, but others are missing and need to be calculated based on purchase date and standard shelf life. You need to create a system to quickly identify which items need immediate attention.

## Starting State

- LibreOffice Calc opens with a partially complete emergency supplies spreadsheet
- Columns: Item Name, Category, Purchase Date, Expiration Date, Quantity, Location, Days Until Expiration (empty), Status (empty)
- Some expiration dates are missing and need to be calculated
- Formula columns need to be populated

## Standard Shelf Life Reference

- **Bottled water**: 2 years from purchase date
- **Canned goods**: 3 years from purchase date (conservative estimate)
- **Batteries (alkaline)**: 5 years from purchase date
- **Batteries (lithium)**: 10 years from purchase date
- **First aid ointments**: 2 years from purchase date
- **Bandages**: 5 years from purchase date
- **Emergency food bars**: 5 years from purchase date

## Required Actions

1. **Fill Missing Expiration Dates**: Review items with blank expiration dates and calculate them using Purchase Date + shelf life (see reference above)

2. **Create Days Until Expiration Formula**: In column G, create a formula that calculates days remaining until expiration using `=DAYS(ExpirationDate, TODAY())` or equivalent

3. **Create Status Categorization Formula**: In column H, create a nested IF formula:
   - If days < 0: "EXPIRED"
   - If days ≤ 30: "IMMEDIATE"
   - If days ≤ 90: "SOON"
   - Otherwise: "OK"

4. **Apply Conditional Formatting to Days Column**: Use color scale (red for urgent, yellow for moderate, green for good)

5. **Apply Conditional Formatting to Status Column**: Use text-based rules:
   - EXPIRED: Dark red background
   - IMMEDIATE: Orange/red background
   - SOON: Yellow background
   - OK: Green background

6. **Sort by Priority**: Sort all data by "Days Until Expiration" (ascending) to bring urgent items to the top

7. **Save the file**

## Success Criteria

1. ✅ **Days Formula Present**: "Days Until Expiration" column contains date calculation formulas
2. ✅ **Days Calculation Accurate**: Spot-checked calculations match expected values (±1 day tolerance)
3. ✅ **Status Formula Present**: "Status" column contains IF statement conditional logic
4. ✅ **Status Categories Correct**: All thresholds properly categorize items (0/30/90 day boundaries)
5. ✅ **Days Formatting Applied**: Conditional formatting exists on days column
6. ✅ **Status Formatting Applied**: Conditional formatting exists on status column
7. ✅ **All Dates Complete**: No missing expiration dates in dataset
8. ✅ **No Formula Errors**: No #REF!, #VALUE!, or other error values present
9. ✅ **Data Sorted by Priority**: Items ordered with soonest expiration first

**Pass Threshold**: 70% (requires at least 5 out of 9 criteria)

## Skills Tested

- Date arithmetic and TODAY() function
- Nested IF statements and conditional logic
- Cell references (absolute vs relative)
- Conditional formatting (color scales and rule-based)
- Data sorting while maintaining integrity
- Problem-solving with incomplete data

## Tips

- Use `=DAYS(D2, TODAY())` or `=D2-TODAY()` for days calculation
- For nested IFs: `=IF(G2<0,"EXPIRED",IF(G2<=30,"IMMEDIATE",IF(G2<=90,"SOON","OK")))`
- Copy formulas down using Ctrl+D or drag fill handle
- Access conditional formatting: Format → Conditional → Condition or Color Scale
- Sort entire dataset: Select all data, then Data → Sort
- Check today's date with Ctrl+; if needed

## Example Formula Logic

**Days Until Expiration (Column G):**