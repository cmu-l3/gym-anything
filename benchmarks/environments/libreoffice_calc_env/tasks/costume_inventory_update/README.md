# LibreOffice Calc Theater Costume Inventory Update Task (`costume_inventory_update@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Cell editing, status updates, conditional formatting, data reconciliation  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Update a theater costume inventory spreadsheet after a production closes. Process returned costumes, mark damaged items, add condition notes, and apply visual formatting to prioritize repairs. This simulates real-world data reconciliation where records must be updated to match physical reality.

## Scenario

**Context**: It's Sunday evening after a production finale. Several costumes were returned but not logged. The next show's first dress rehearsal is Tuesday, and the director needs a damage report by Monday morning. The costume manager must quickly update the spreadsheet to reflect reality and highlight items needing repair.

## Task Description

The agent must:
1. Locate returned items currently marked as "Checked Out"
2. Update their Status to "Available"
3. Mark damaged items by changing Condition to "Damaged"
4. Add specific damage notes in the Notes column
5. Apply conditional formatting to visually highlight damaged items
6. Save the file

## Initial Data

The spreadsheet contains costume inventory with columns:
- **Item ID**: Unique identifier (e.g., C005)
- **Item Name**: Name of costume/accessory
- **Type**: Costume or Accessory
- **Size**: S, M, L, or One Size
- **Character**: Show character who wore it
- **Status**: Available, Checked Out, In Repair
- **Condition**: Good, Damaged, Needs Cleaning
- **Notes**: Additional information

## Required Updates

### Returned Items (Status: Checked Out → Available)
- **Row 6**: Victorian Jacket
- **Row 9**: Medieval Tunic  
- **Row 12**: Top Hat

### Damaged Items (Condition: Good → Damaged, add Notes)
- **Row 6**: Victorian Jacket
  - Condition: "Damaged"
  - Notes: "Torn sleeve, needs stitching" (or similar damage description)
  
- **Row 9**: Medieval Tunic
  - Condition: "Damaged"
  - Notes: "Wine stain on front, requires cleaning" (or similar damage description)

### Conditional Formatting
- Apply conditional formatting to the **Condition column (G)** 
- Rule: Cells containing "Damaged" should be highlighted (red/orange background)
- This helps the repair team quickly identify priority items

## Expected Results

After task completion:
- Victorian Jacket: Status="Available", Condition="Damaged", Notes with damage description
- Medieval Tunic: Status="Available", Condition="Damaged", Notes with damage description
- Top Hat: Status="Available", Condition remains "Good"
- Damaged items visually highlighted in Condition column
- Other inventory items unchanged

## Verification Criteria

1. ✅ **Status Updates Complete**: Victorian Jacket, Medieval Tunic, Top Hat marked "Available"
2. ✅ **Damage Marked**: Victorian Jacket and Medieval Tunic Condition set to "Damaged"
3. ✅ **Notes Added**: Damage descriptions present in Notes column for damaged items
4. ✅ **Conditional Formatting Applied**: Damaged items visually highlighted
5. ✅ **Data Integrity Maintained**: Other items and columns unchanged

**Pass Threshold**: 70% (requires at least 3 out of 5 criteria)

## Skills Tested

- **Cell Navigation**: Move to specific cells for editing
- **Data Entry**: Update categorical values (Status, Condition)
- **Text Entry**: Add descriptive notes
- **Conditional Formatting**: Create and apply formatting rules
- **Multi-step Workflow**: Coordinate multiple related updates
- **Data Reconciliation**: Update records to match physical reality
- **Visual Management**: Use formatting to communicate priorities

## Tips

- Use Ctrl+Home to return to cell A1
- Use arrow keys or mouse to navigate to specific cells
- Double-click or press F2 to edit cell contents
- Access conditional formatting: Format → Conditional Formatting → Condition...
- Select column G range (e.g., G2:G13) before applying formatting
- Create rule: "Cell value is" "equal to" "Damaged"
- Choose a visible highlight color (light red or orange)
- Press Ctrl+S to save when complete

## Setup

The setup script:
- Creates costume inventory CSV with 12 items
- Three items marked as "Checked Out" (Victorian Jacket, Medieval Tunic, Top Hat)
- Launches LibreOffice Calc with the inventory
- Focuses the Calc window

## Export

The export script:
- Saves the file as `/home/ga/Documents/costume_inventory_updated.ods`
- Closes LibreOffice Calc

## Verification

Verifier checks:
1. Specific cell values for Status updates (column F, rows 6, 9, 12)
2. Specific cell values for Condition updates (column G, rows 6, 9)
3. Presence of damage-related keywords in Notes (column H, rows 6, 9)
4. Conditional formatting rules applied to Condition column
5. Data integrity for unchanged items

## Real-World Application

This task represents common workflows in:
- Theater costume departments
- Equipment lending libraries
- Tool checkout systems
- Rental inventory management
- Asset tracking with condition monitoring
- Any system where physical items must be reconciled with database records