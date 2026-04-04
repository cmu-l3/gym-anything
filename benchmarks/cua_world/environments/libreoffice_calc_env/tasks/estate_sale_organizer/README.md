# Estate Sale Emergency Organizer Task

**Difficulty**: 🟡 Medium  
**Skills**: Data consolidation, conflict detection, VLOOKUP, conditional logic, text parsing  
**Duration**: 240 seconds  
**Steps**: ~15

## Objective

Consolidate a messy estate sale inventory from multiple inconsistent sources, detect conflicting item assignments, separate sellable items from keepsakes, standardize price formats, and flag urgent family conflicts. This simulates helping a relative organize an estate sale under time pressure with incomplete information.

## Task Description

You must organize estate sale data spread across three messy sheets:

### Source Sheets:
1. **Main_Inventory**: Primary item list with descriptions and estimated values (40+ items)
   - Columns: Item, Description, Estimated_Value (mixed formats like "$50-75", "around 100", "200")
   
2. **Family_Promises**: Items promised to family members (15 items)
   - Columns: Item_Name, Promised_To
   - **CRITICAL**: Some items appear multiple times with different family members (conflicts!)
   
3. **Sentimental_Keep**: Items with sentimental value that CANNOT be sold (8 items)
   - Columns: Item, Reason

### Required Actions:

1. **Create Consolidated Sheet**:
   - Merge all data from Main_Inventory
   - Add columns: Item Name, Description, Estimated Value (Low), Estimated Value (High), Status, Assigned To, Conflict Flag
   - Cross-reference with Family_Promises and Sentimental_Keep

2. **Detect Conflicts**:
   - Use COUNTIF or similar to detect items promised to multiple people
   - Flag with "URGENT - Multiple Claims" in Conflict Flag column
   - Highlight conflicts visually (conditional formatting)

3. **Mark Sentimental Items**:
   - Check items against Sentimental_Keep sheet
   - Mark Status as "DO NOT SELL" for matches

4. **Standardize Prices**:
   - Parse text like "$50-75" → Low: 50, High: 75
   - "around 100" → Low: 90, High: 110
   - "200" → Low: 200, High: 200

5. **Create For_Sale Sheet**:
   - Filter items that CAN be sold (not sentimental, no conflicts)
   - Calculate total estimated value range

6. **Create Urgent_Conflicts Sheet**:
   - List all items with multiple family claims
   - Include all relevant details for family discussion

## Expected Results

### Consolidated Sheet:
- All items from Main_Inventory with enriched data
- Proper Status and Assigned To columns populated
- Conflict flags for disputed items

### For_Sale Sheet:
- **ONLY** items that can legally be sold:
  - NOT in Sentimental_Keep list
  - Status is NOT "DO NOT SELL"
  - NO unresolved conflicts
- Total sale value calculated

### Urgent_Conflicts Sheet:
- All items flagged as conflicts
- Shows competing family member claims

## Verification Criteria

1. ✅ **All Items Consolidated**: Every item from source sheets in Consolidated (100% capture)
2. ✅ **Conflicts Detected**: Items promised to multiple people are flagged correctly
3. ✅ **Sale Filter Accurate**: For_Sale contains ONLY sellable items (no keepsakes, no conflicts)
4. ✅ **Prices Standardized**: Values converted to numeric Low/High ranges
5. ✅ **Totals Calculated**: Sale value totals computed correctly
6. ✅ **Urgent Sheet Created**: Conflict resolution sheet exists with flagged items
7. ✅ **No Sentimental Items for Sale**: Zero items from Sentimental_Keep in For_Sale

**Pass Threshold**: 75% (requires 5-6 out of 7 criteria)

## Skills Tested

- Multi-sheet navigation and cross-referencing
- VLOOKUP or INDEX-MATCH for lookups
- COUNTIF for duplicate detection
- IF statements for conditional logic
- Text functions (VALUE, LEFT, RIGHT, MID)
- Conditional formatting
- Data filtering and sheet organization
- SUM formulas for totals

## Why This Matters

This represents a real crisis: helping family downsize under time pressure with incomplete, emotionally-charged data. Getting it wrong causes family conflicts or loses valuable items. The agent must understand business rules, detect problems, and create actionable outputs for estate sale professionals.