# Manage Inventory Shrinkage (`manage_inventory_shrinkage@1`)

## Overview
This task evaluates the agent's ability to manage inventory discrepancies in NCH Copper Point of Sale. The agent must create a new inventory item record to reflect a received shipment, and then correctly process a stock adjustment (shrinkage) to account for units that arrived damaged, ensuring the inventory count and value are accurate.

## Rationale
**Why this task is valuable:**
- Tests the critical retail workflow of "Inventory Shrinkage" management (loss prevention/accounting).
- Requires navigating distinct application modules: Item creation (receiving) and Quantity Adjustment (inventory control).
- Verifies the ability to document *reasons* for data changes (audit trail), not just changing numbers.
- Reflects a real-world supply chain issue where physical goods don't match the invoice due to damage.

**Real-world Context:** A shipment of high-end glassware has arrived at the store. The invoice lists 12 units, but upon opening the box, the manager discovers that 3 units are shattered. The item must be entered into the system as invoiced (to match the supplier bill), and then the broken units must be written off with a specific reason code for insurance and tax purposes.

## Task Description

**Goal:** Add a new product "Crystal Wine Decanter" to the inventory with the shipment quantity of 12, and immediately record a shrinkage adjustment of 3 broken units so the final sellable stock is 9.

**Starting State:**
- NCH Copper Point of Sale is open and maximized.
- The item "Crystal Wine Decanter" does **not** yet exist in the system.

**Detailed Instructions:**

1. **Create the New Item:**
   - Navigate to the Item List / Inventory management screen.
   - Add a new item with the following details:
     - **Item Code/Name:** Crystal Wine Decanter
     - **Description:** 750ml Lead-Free Crystal Decanter
     - **Unit Cost:** $25.00
     - **Unit Sales Price:** $45.00
     - **Tax:** (Use default or standard tax)
     - **Initial Quantity:** 12 (This represents the invoiced amount)

2. **Process Stock Adjustment (Shrinkage):**
   - Locate the newly created item.
   - Use the "Adjust Quantity" (or similar) feature to remove the broken units.
   - **Adjustment Amount:** -3 (Remove 3 units)
   - **Reason/Note:** Enter exactly: "Shipping Damage"
   - Save the adjustment.

3. **Verify Final State:**
   - Ensure the item "Crystal Wine Decanter" lists exactly **9** units in stock.
   - Ensure the adjustment is recorded in the system.

**Final State:**
- Item "Crystal Wine Decanter" exists.
- Current Quantity is 9.
- An adjustment history record exists with the note "Shipping Damage".

## Verification Strategy

### Primary Verification: Database/Data File Inspection
The verifier will scan NCH Copper's local data files (typically in `%ProgramData%\NCH Software\Copper` or `%AppData%`) to validate the item and its movement.

1. **Item Existence & Pricing Check:**
   - Search for an item record matching "Crystal Wine Decanter".
   - Verify `UnitCost` == 25.00 and `UnitPrice` == 45.00.

2. **Stock Level Verification:**
   - Verify the current `Quantity` field for this item is exactly **9**.

3. **Adjustment History Verification:**
   - Search the transaction/inventory log table or file for a record linked to this item.
   - Verify an entry exists with the text "Shipping Damage" (case-insensitive).
   - Verify the quantity change associated with this note is -3 (or a movement from 12 to 9).

### Secondary Verification: VLM Trajectory Analysis
- **Creation Step:** Screenshot should show the "New Item" form filled with "Crystal Wine Decanter" and Quantity "12".
- **Adjustment Step:** Screenshot should show the "Adjust Quantity" dialog (or similar interface) with "-3" and the note "Shipping Damage".
- **Final Result:** Final screenshot should show the Item List with "Crystal Wine Decanter" highlighting a stock count of "9".

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Item Created | 20 | "Crystal Wine Decanter" found in database |
| Pricing Accuracy | 10 | Cost ($25) and Price ($45) match exactly |
| Initial/Invoiced Qty Logic | 10 | Evidence that initial state was 12 (via logs or VLM) |
| Shrinkage Recorded | 30 | Current Quantity is exactly 9 |
| Audit Note Accuracy | 30 | "Shipping Damage" note found in adjustment logs |
| **Total** | **100** | |

**Pass Threshold:** 70 points (Must have correct final quantity and item existence).