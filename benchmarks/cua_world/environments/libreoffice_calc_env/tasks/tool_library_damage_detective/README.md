# Tool Library Damage Detective Task

**Difficulty**: 🟡 Medium  
**Skills**: VLOOKUP/XLOOKUP, date calculations, multi-sheet navigation, data updates  
**Duration**: 180 seconds (3 minutes)  
**Steps**: ~15

## Objective

Investigate a damaged tool return in a community tool lending library. Determine who was the last borrower, check if they returned it late, update the tool's condition status, and flag the member for follow-up contact. This task tests lookup formulas, date calculations, and multi-sheet data management in a realistic scenario.

## Starting State

LibreOffice Calc opens with a tool library workbook containing three sheets:
1. **Inventory**: 30 tools with current status
2. **BorrowingLog**: Complete borrowing history (50+ records)
3. **Members**: Contact information for 20 library members

**Scenario**: The "Post Hole Digger" (Tool ID: T-047) was just returned with bent handles (significant damage requiring repair).

## Required Actions

### Investigation Steps:
1. Navigate to **BorrowingLog** sheet
2. Find all entries for Tool ID "T-047"
3. Identify the most recent borrower (latest checkout date)
4. Note the Member ID of last borrower

### Lookup Member Information:
5. Use VLOOKUP or XLOOKUP to retrieve borrower's name from **Members** sheet
6. Retrieve their contact email/phone

### Calculate Borrowing Details:
7. Determine checkout and return dates
8. Calculate total days borrowed
9. Check if overdue (policy: 7-day max borrowing period)

### Update Records:
10. Go to **Inventory** sheet
11. Find Tool ID T-047 row
12. Update "Condition" from "Good" to "Damaged" or "Needs Repair"
13. Update "Available" to "No"

### Flag Member:
14. Go to **Members** sheet
15. Find responsible member's row
16. Set "PendingContact" column to "YES"

### Document Investigation:
17. Create investigation summary with:
    - Last Borrower name (from lookup)
    - Member ID
    - Checkout/Return dates
    - Days borrowed
    - Overdue status (YES/NO)
    - Contact email

## Expected Results

- **Last Borrower**: Member M-023 (Sarah Chen) correctly identified
- **VLOOKUP Formula**: Used to retrieve member name and email
- **Tool Status**: T-047 marked as "Damaged" or "Needs Repair"
- **Availability**: T-047 marked as "No" (unavailable)
- **Member Flagged**: Sarah Chen has "PendingContact" = YES
- **Duration**: Calculated as 9 days (overdue by 2 days)
- **Contact Info**: sarah.chen@email.com retrieved

## Success Criteria

1. ✅ **Correct Last Borrower**: Member M-023 (Sarah Chen) identified
2. ✅ **Lookup Formula Used**: VLOOKUP/XLOOKUP for member information
3. ✅ **Tool Status Updated**: T-047 marked as damaged/unavailable
4. ✅ **Member Flagged**: M-023 has PendingContact = YES
5. ✅ **Duration Calculated**: 9 days computed via formula
6. ✅ **Overdue Detected**: Correctly identified as overdue
7. ✅ **Contact Retrieved**: Email retrieved via formula

**Pass Threshold**: 70% (5 out of 7 criteria must pass)

## Skills Tested

- Multi-sheet navigation and data management
- VLOOKUP/XLOOKUP for cross-referencing data
- Date arithmetic and calculations
- Conditional logic (overdue determination)
- Data updates and record maintenance
- Investigation and analytical thinking

## Tips

- Sort BorrowingLog by ToolID or Date to find T-047 records easily
- Use VLOOKUP syntax: `=VLOOKUP(lookup_value, table_range, col_index, FALSE)`
- For dates: `=ReturnDate - CheckoutDate` gives days borrowed
- Check if days > 7 to determine overdue status
- Use absolute references ($) in formulas for sheet references
- Investigation results can go in a new sheet or designated area

## Data Structure

### Inventory Sheet
| Tool ID | Tool Name | Category | Condition | Purchase Date | Available |
|---------|-----------|----------|-----------|---------------|-----------|
| T-047   | Post Hole Digger | Yard | Good | 2021-03-15 | Yes |

### BorrowingLog Sheet
| LogID | ToolID | MemberID | CheckoutDate | ReturnDate | ConditionOut | ConditionBack |
|-------|--------|----------|--------------|------------|--------------|---------------|
| L-089 | T-047  | M-023    | [9 days ago] | [today]    | Good         | Damaged       |

### Members Sheet
| MemberID | Name | Email | Phone | JoinDate | GoodStanding | PendingContact |
|----------|------|-------|-------|----------|--------------|----------------|
| M-023    | Sarah Chen | sarah.chen@email.com | 555-0123 | 2022-01-10 | Yes | [empty] |