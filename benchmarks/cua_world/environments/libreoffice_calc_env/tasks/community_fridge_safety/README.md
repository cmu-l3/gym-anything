# Community Fridge Safety Manager Task

**Difficulty**: 🟡 Medium  
**Skills**: Date calculations, conditional formatting, data sorting, formula creation  
**Duration**: 180 seconds  
**Steps**: ~25

## Objective

Manage a community fridge inventory spreadsheet to prevent food waste and health violations. Calculate days until expiration, apply visual warnings through conditional formatting, and sort items by urgency to help volunteers identify what needs immediate removal.

## Task Description

The agent must:
1. Open a community fridge inventory CSV file containing:
   - Column A: Item Name (e.g., "Milk - 2%", "Yogurt")
   - Column B: Donation Date
   - Column C: Expiration Date
   - Column D: Volunteer Name (who stocked it)
2. Create a new column E: "Days Until Expiration"
3. Add formula in column E to calculate days remaining (Expiration Date - TODAY())
4. Apply conditional formatting to column E:
   - RED background (white text) for items with ≤3 days remaining (critical)
   - YELLOW background (black text) for items with 4-7 days remaining (warning)
5. Sort all data by "Days Until Expiration" (ascending - most urgent first)
6. Save the file as ODS

## Expected Results

- **Column E** contains formula `=C2-TODAY()` (or similar) for each data row
- **Critical items** (≤3 days) highlighted in RED
- **Warning items** (4-7 days) highlighted in YELLOW
- **Data sorted** with most urgent items (expired/expiring soon) at the top
- **Row integrity** maintained (item names match their expiration dates)

## Verification Criteria

1. ✅ **Formula Present**: Days Until Expiration column exists with correct formula
2. ✅ **Critical Formatting**: Items with ≤3 days have RED background
3. ✅ **Warning Formatting**: Items with 4-7 days have YELLOW background
4. ✅ **Sorted Correctly**: Data sorted ascending by Days Until Expiration
5. ✅ **Row Integrity**: No data corruption during sort

**Pass Threshold**: 80% (4/5 criteria must pass)

## Skills Tested

- Date arithmetic and TODAY() function
- Formula creation and copying
- Conditional formatting with multiple rules
- Multi-criteria color-coded systems
- Data sorting with header preservation
- Food safety awareness

## Real-World Context

Community fridges serve vulnerable populations and must comply with health regulations. This spreadsheet helps volunteers:
- Identify food that must be removed immediately (red items)
- Proactively distribute food before it expires (yellow items)
- Maintain accountability (track which volunteers need training)
- Prevent health violations that could shut down the resource

## Setup

The setup script:
- Creates a CSV file with community fridge inventory data
- Includes items with various expiration dates (some already expired, some expiring soon)
- Launches LibreOffice Calc with the CSV file
- Positions cursor at cell A1

## Export

The export script:
- Saves the file as `/home/ga/Documents/community_fridge_sorted.ods`
- Closes LibreOffice Calc

## Verification

Verifier parses the ODS file and checks:
1. Column E contains formulas referencing dates and TODAY()
2. Cell styles in column E for items ≤3 days have red backgrounds
3. Cell styles in column E for items 4-7 days have yellow backgrounds
4. Column E values are in ascending order
5. Item names correctly correspond to their expiration dates