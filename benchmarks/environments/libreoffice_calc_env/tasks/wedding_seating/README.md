# Wedding Seating Arrangement Task

**Difficulty**: 🟡 Medium  
**Skills**: Constraint planning, formula creation, data organization, logical reasoning  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Organize wedding reception seating arrangements from a guest list with family groupings. Assign each confirmed guest to a table number while respecting capacity constraints (8 people per table), keeping family units together, and creating a summary table with formulas to track table occupancy.

## Task Description

The agent must:
1. Review the guest list spreadsheet with 64 confirmed guests
2. Understand constraints: 8-person max per table, keep families together
3. Assign Wedding Party (8 people) to Table 1
4. Assign remaining family groups to tables 2-10
5. Create a summary table showing guest count per table using COUNTIF formulas
6. Ensure no table exceeds capacity

## Starting State

- LibreOffice Calc opens with guest list
- **Column A**: Guest Name
- **Column B**: Family/Group designation
- **Column C**: Meal Preference
- **Column D**: Table Assignment (empty - to be filled)
- Rows 3-66: 64 guests with family groupings

## Guest List Structure

- **Wedding Party**: 8 people (must be at Table 1)
- **Smith Family**: 6 people
- **Johnson Family**: 5 people  
- **Garcia Family**: 4 people
- **Chen Family**: 4 people
- Several smaller families and individual guests

## Required Actions

1. **Assign Wedding Party**: All 8 Wedding Party members to Table 1
2. **Assign Families**: Keep each family group at same table when possible
3. **Assign Individuals**: Place remaining guests to fill tables efficiently
4. **Create Summary Table**:
   - Headers in F2:G2 ("Table Number", "Guest Count")
   - Table numbers in column F (1, 2, 3, etc.)
   - COUNTIF formulas in column G to count guests per table
5. **Verify Constraints**: No table exceeds 8 guests

## Success Criteria

1. ✅ **All Guests Assigned**: No empty cells in Table Assignment column (Column D)
2. ✅ **Capacity Respected**: No table has more than 8 guests
3. ✅ **Wedding Party Correct**: All 8 Wedding Party members at Table 1, exclusively
4. ✅ **Families Together**: At least 80% of family groups seated together
5. ✅ **Summary Table Exists**: Valid summary with headers in F2:G2
6. ✅ **Summary Accurate**: Column G contains COUNTIF formulas that correctly count assignments

**Pass Threshold**: 70% (4 out of 6 criteria must pass)

## Skills Tested

- Constraint satisfaction planning
- Systematic data entry
- COUNTIF formula creation
- Capacity management
- Logical reasoning about relationships
- Cell reference usage (absolute vs relative)

## Verification Strategy

The verifier checks:
- Complete assignment (all 64 guests have table numbers)
- Capacity constraints (max 8 per table via COUNTIF)
- Wedding Party placement (exactly 8 at Table 1)
- Family cohesion (same family = same table)
- Summary table structure and formulas
- Formula accuracy (formulas match actual counts)

## Tips

- Start with Wedding Party at Table 1 (fixed constraint)
- Work through families systematically
- Use consistent table numbering (1, 2, 3, etc.)
- COUNTIF syntax: `=COUNTIF($D$3:$D$66, F3)`
- Use absolute references ($D$3:$D$66) for data range
- Use relative reference (F3) for table number to auto-fill formula