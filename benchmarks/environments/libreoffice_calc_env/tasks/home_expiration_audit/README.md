# Home Expiration Audit Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, date formulas, conditional formatting, analysis  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~30

## Objective

Clean and analyze a messy home inventory audit list containing expired and expiring items from your medicine cabinet, pantry, and first aid kit. Transform inconsistent human-entered data into a structured, actionable report with visual formatting and waste analysis.

## Task Description

You've just completed a spring cleaning audit of your home, checking expiration dates on medications, food items, and personal care products. You made a quick messy list while going through everything. Now you need to:

1. **Clean the data**: Standardize inconsistent location names, category labels, and item descriptions
2. **Parse dates**: Convert various date formats to a consistent standard
3. **Calculate urgency**: Determine days until expiration and priority levels
4. **Apply visual formatting**: Color-code items by urgency (red=expired, orange=urgent, yellow=expiring soon, green=good)
5. **Analyze waste**: Identify items that expired long before use, calculate waste costs
6. **Sort by priority**: Organize items by replacement urgency
7. **Generate insights**: Create summary statistics about expiration patterns

## Starting Data Structure

The CSV file contains messy, human-entered data:

| Item Name | Location | Expiration Date | Status | Purchase Price | Category |
|-----------|----------|----------------|--------|---------------|----------|
| aspirin 100ct | medicine cab | 03/15/2024 | kept | 8.99 | Meds |
| Ibuprofen 200mg | Medicine Cabinet | June 2024 | kept | 12.50 | medication |
| BAND AIDS | first aid | 12/01/2023 | discarded | 5.99 | first aid |

**Data issues to fix**:
- Inconsistent capitalization
- Multiple date formats (MM/DD/YYYY, "Month YYYY", "Best by...")
- Varying location names ("medicine cab" vs "Medicine Cabinet")
- Different category spellings ("Meds" vs "medication" vs "Medicine")
- Missing data in some cells

## Required Actions

### Phase 1: Data Cleaning (Steps 1-10)
1. Open the CSV file in LibreOffice Calc
2. Standardize Location names:
   - All "medicine cab" variants → "Medicine Cabinet"
   - All "pantry" variants → "Pantry"  
   - All "bathroom" variants → "Bathroom"
   - All "first aid" variants → "First Aid Kit"
3. Normalize Category names:
   - All medication variants → "Medication"
   - All food variants → "Food"
   - All personal care variants → "Personal Care"
4. Clean item names (remove extra spaces, fix capitalization)
5. Standardize all dates to MM/DD/YYYY format

### Phase 2: Add Calculated Columns (Steps 11-18)
6. Add column "Days Until Expiration": `=Expiration_Date - TODAY()`
7. Add column "Status Category": 
   - "EXPIRED" if days < 0
   - "URGENT" if 0-30 days
   - "EXPIRING SOON" if 31-90 days
   - "GOOD" if > 90 days
8. Add column "Replacement Priority": 1 (highest) to 4 (lowest)
9. Add column "Waste Flag": Mark items discarded 180+ days after expiration

### Phase 3: Visual Formatting (Steps 19-22)
10. Apply conditional formatting:
    - Red background: EXPIRED items
    - Orange background: URGENT items
    - Yellow background: EXPIRING SOON items
    - Green background: GOOD items

### Phase 4: Organization (Steps 23-25)
11. Sort data:
    - Primary: Replacement Priority (ascending)
    - Secondary: Days Until Expiration (ascending)

### Phase 5: Summary Analysis (Steps 26-30)
12. Create summary section with:
    - Total items audited
    - Count of expired items
    - Count of urgent items
    - Total waste cost
    - Waste breakdown by category

## Expected Results

**Cleaned data with**:
- Standardized location and category names (100% consistency)
- Uniform date formats
- Calculated columns showing days until expiration
- Status categories properly assigned
- Color-coded rows by urgency

**Summary section showing**:
- Total Items: ~20
- Expired Items: ~3-4
- Urgent Items: ~2-3
- Total Waste Cost: Calculated from discarded items
- Most Wasted Category: Analysis of which category wastes most

## Success Criteria

1. ✅ **Data Standardization**: Locations and categories use consistent naming (≥85%)
2. ✅ **Date Calculations**: Days until expiration formulas present and accurate
3. ✅ **Status Classification**: Status categories correctly assigned (≥3 types)
4. ✅ **Conditional Formatting**: Color coding applied (multiple status categories)
5. ✅ **Summary Statistics**: Count formulas present (≥3)
6. ✅ **Waste Analysis**: Waste cost calculation or flag column present
7. ✅ **Sorting**: Data sorted by priority/urgency
8. ✅ **File Saved**: Output file exists in ODS format

**Pass Threshold**: 75% (6 out of 8 criteria)

## Skills Tested

- Data cleaning and standardization (TRIM, SUBSTITUTE, UPPER/LOWER, PROPER)
- Date parsing and arithmetic (TODAY, DATEVALUE, date differences)
- Conditional logic (IF, AND, OR statements)
- Formula creation and cell references
- Conditional formatting with rules
- Multi-level sorting
- Statistical functions (COUNT, COUNTIF, SUM, SUMIF)
- Data aggregation and analysis
- Practical decision making from data

## Tips

- Use Find & Replace (Ctrl+H) for standardizing repeated text
- TRIM() removes extra spaces, PROPER() fixes capitalization
- DATEVALUE() converts text dates to proper date format
- TODAY() gives current date for calculating days remaining
- Conditional formatting: Format → Conditional Formatting → Condition
- Multi-level sort: Data → Sort, add multiple sort keys
- Use absolute references ($A$1) for TODAY() comparisons