# Plant Watering Scheduler Task

**Difficulty**: 🟡 Medium  
**Skills**: Date formulas, TODAY() function, conditional formatting, data sorting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Create a practical plant care tracker that helps an indoor plant enthusiast manage different watering schedules. The spreadsheet must calculate next watering dates, highlight overdue plants, and sort by priority.

## Task Description

You are a plant enthusiast with multiple houseplants that have different watering needs. You need a spreadsheet that:
1. Tracks when each plant was last watered
2. Calculates when each plant needs watering next
3. Shows how many days until the next watering
4. **Visually highlights overdue plants in red**
5. **Sorts plants by urgency** (most overdue first)

## Required Actions

### 1. Create Column Headers
Set up the following columns (A1-E1):
- A1: "Plant Name"
- B1: "Watering Frequency (Days)"
- C1: "Last Watered"
- D1: "Next Watering Date"
- E1: "Days Until Next Watering"

### 2. Enter Plant Data (at least 5 plants)
Starting in row 2, enter plant information. Example data:

| Plant Name | Frequency | Last Watered | Next Watering | Days Until |
|------------|-----------|--------------|---------------|------------|
| Succulent | 14 | (recent date) | (formula) | (formula) |
| Fern | 3 | (old date) | (formula) | (formula) |
| Spider Plant | 7 | (mid date) | (formula) | (formula) |
| Pothos | 5 | (recent date) | (formula) | (formula) |
| Snake Plant | 10 | (mid date) | (formula) | (formula) |
| Peace Lily | 4 | (old date) | (formula) | (formula) |

**Important**: At least 2 plants should have old "Last Watered" dates to create overdue situations.

### 3. Create Next Watering Date Formula
In cell D2, enter: `=C2+B2`
- This adds the watering frequency to the last watered date
- Copy formula down to all plant rows (D2:D7)

### 4. Create Days Until Next Watering Formula
In cell E2, enter: `=D2-TODAY()`
- This calculates days remaining until next watering
- Negative values mean the plant is overdue
- Copy formula down to all plant rows (E2:E7)

### 5. Apply Conditional Formatting
- Select the "Days Until Next Watering" column (E2:E7)
- Navigate to **Format → Conditional Formatting → Condition**
- Set condition: **"Cell value is less than 0"**
- Set format: **Red background or red text**
- Apply the rule

### 6. Sort Plants by Priority
- Select entire data range including headers (A1:E7)
- Navigate to **Data → Sort**
- Sort by: "Days Until Next Watering" (column E)
- Order: **Ascending** (most negative/overdue first)
- Ensure "Range contains column labels" is checked
- Apply sort

### 7. Verify
Check that:
- Overdue plants (negative days) appear at top
- Overdue plants are highlighted in red
- Formulas update automatically

## Expected Results

- **D2:D7** contain formulas `=C2+B2` (or equivalent cell references)
- **E2:E7** contain formulas `=D2-TODAY()` (or equivalent)
- **Conditional formatting** highlights cells in column E where value < 0
- **Data sorted** by column E in ascending order (most urgent first)
- **At least one plant** is overdue and highlighted

## Success Criteria

1. ✅ **Data Structure**: At least 5 plants with all 5 columns populated
2. ✅ **Next Watering Formula**: Correct pattern `=LastWatered+Frequency` in column D
3. ✅ **Days Until Formula**: Correct pattern `=NextWatering-TODAY()` in column E
4. ✅ **Conditional Formatting**: Red highlighting applied to negative values
5. ✅ **Sorted by Priority**: Data sorted ascending by Days Until (overdue first)
6. ✅ **Calculation Accuracy**: Formula results are mathematically correct
7. ✅ **Visual Urgency**: At least one overdue plant exists and is highlighted

**Pass Threshold**: 70% (requires at least 5 out of 7 criteria)

## Skills Tested

- Date arithmetic and formula creation
- TODAY() function for dynamic calculations
- Conditional formatting with conditions
- Data sorting by calculated columns
- Formula dependencies (chained formulas)
- Practical spreadsheet design

## Tips

- Use dates in format: YYYY-MM-DD, MM/DD/YYYY, or DD/MM/YYYY
- To create overdue plants: enter "Last Watered" dates 5-10 days ago
- Formulas should reference cells, not hardcode values
- Conditional formatting is in Format menu, not Home/Insert
- Sort the entire range including headers
- Verify your work: negative values should be red and at the top

## Real-World Context

This tracker helps plant owners:
- Never miss a watering day
- Prioritize urgent care needs
- Manage plants with different schedules
- See at-a-glance what needs attention TODAY