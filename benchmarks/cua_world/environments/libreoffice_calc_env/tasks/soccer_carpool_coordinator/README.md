# Soccer Carpool Coordinator Task

**Difficulty**: 🟡 Medium  
**Skills**: Data analysis, formula creation, conditional formatting, constraint validation  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Manage a soccer team carpool spreadsheet after a family unexpectedly drops out mid-season. Fill coverage gaps, verify vehicle capacity constraints, apply conditional formatting to highlight problems, and calculate fair gas cost reimbursement based on miles driven.

## Scenario Context

**The Situation:**
You're coordinating carpools for the Riverside Youth Soccer team's twice-weekly practices. The team has 12 kids from 8 different families, with practices held at a field varying distances from each family's home.

**The Crisis:**
The Martinez family has unexpectedly moved out of town. Their two kids are no longer on the team, and their 6 scheduled driving dates are now empty. You must:
1. Identify which dates have no driver (Martinez slots)
2. Reassign drivers from available families
3. Ensure vehicle capacity limits aren't exceeded
4. Calculate fair gas reimbursement based on miles driven
5. Apply conditional formatting to flag problems

## Starting State

LibreOffice Calc opens with a partially-filled carpool spreadsheet containing:
- **Column A:** Practice dates (12 remaining dates)
- **Column B:** Assigned driver family name (6 show "Martinez" - these need replacement)
- **Column C:** Vehicle type (Sedan/SUV/Minivan)
- **Column D:** Vehicle capacity (passengers only, not including driver)
- **Column E:** Number of kids assigned to ride
- **Column F:** Miles driven (round trip)
- **Columns H-K:** Family information reference table
- **Notes section:** Lists which families cannot drive certain days

## Family Information

| Family | Vehicle Type | Kids | Miles to Field |
|--------|-------------|------|----------------|
| Johnson | SUV | 2 | 16 |
| Thompson | Sedan | 1 | 12 |
| Chen | Minivan | 2 | 20 |
| Patel | Sedan | 1 | 10 |
| Williams | SUV | 2 | 18 |
| Davis | Minivan | 1 | 14 |
| Rodriguez | SUV | 1 | 22 |
| Kim | Sedan | 2 | 16 |

**Vehicle Capacities:**
- Sedan: 4 passengers
- SUV: 6 passengers  
- Minivan: 7 passengers

**Constraints:**
- Johnson family: Already driving 5 times, prefer not to add more
- Thompson: Cannot drive Tuesdays (work conflict)
- Chen: Cannot drive Thursdays (care for elderly parent)
- Patel: Only has sedan (capacity 4), be mindful of passenger count

## Required Actions

### 1. Identify Coverage Gaps
- Find all dates where Column B shows "Martinez"
- These 6 dates need new driver assignments

### 2. Reassign Drivers
- For each Martinez date, assign a replacement family
- Check day of week against availability constraints
- Ensure the replacement family's vehicle can accommodate passenger count (Column E)
- Try to balance driving burden fairly

### 3. Update Vehicle Information
- When assigning a new driver, update Column C (vehicle type) and Column D (capacity)
- Update Column F (miles) based on that family's distance

### 4. Apply Conditional Formatting
- **Column E (Kids Assigned):**
  - Red highlight if passengers exceed capacity (E > D)
  - Yellow highlight if at capacity (E = D)
- **Column B (Driver):**
  - Red highlight if empty or still shows "Martinez"

### 5. Calculate Gas Reimbursement
- In the calculation area (around rows 20-30), create formulas:
  - Count trips per family: `=COUNTIF($B$2:$B$13, "Johnson")`
  - Sum miles per family: `=SUMIF($B$2:$B$13, "Johnson", $F$2:$F$13)`
  - Calculate total miles driven by all families
  - Calculate each family's gas share: `(family_miles / total_miles) × $240`

### 6. Save the File
- File is automatically saved as `carpool_schedule.ods`

## Success Criteria

1. ✅ **All Gaps Filled:** No empty drivers, no "Martinez" entries remain
2. ✅ **Capacity Respected:** No date exceeds vehicle passenger capacity
3. ✅ **Formulas Correct:** COUNTIF, SUMIF, and reimbursement calculations are accurate
4. ✅ **Conditional Formatting Applied:** Rules exist for capacity warnings and missing drivers
5. ✅ **Fair Distribution:** No family drives more than 4 times (if possible)
6. ✅ **Mathematical Consistency:** Total reimbursements sum to ~$240

**Pass Threshold**: 70% (requires at least 4 out of 6 criteria)

## Skills Tested

- **Data Analysis:** Scanning spreadsheet to identify problems
- **Formula Creation:** COUNTIF, SUMIF, arithmetic calculations
- **Conditional Formatting:** Creating rules based on cell comparisons
- **Constraint Satisfaction:** Ensuring capacity limits are respected
- **Logical Reasoning:** Balancing multiple competing constraints
- **Cell References:** Using absolute ($) and relative references correctly

## Tips

- Start by identifying all Martinez entries (Ctrl+F to search)
- Reference the family info table to get vehicle types and distances
- Check the Notes section for availability constraints
- Use conditional formatting AFTER filling in assignments
- Formula references should use absolute references ($B$2:$B$13) for ranges
- The total gas fund is $240 - all family shares should sum to this amount