# Library Book Due Date Crisis Manager Task

**Difficulty**: 🟡 Medium  
**Skills**: Date arithmetic, conditional logic, data organization, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Manage a messy dataset of library books with varying due dates, renewal limits, and late fee calculations. Help an overwhelmed library patron avoid late fees by calculating due dates, identifying renewal eligibility, computing potential late fees, prioritizing returns, and applying visual formatting.

## Scenario

You're helping a friend who's an avid reader manage their library books across multiple branches. They've been tracking checkouts manually but are overwhelmed and worried about late fees. Some books might already be overdue! You need to organize this data to help them prioritize which books to return or renew first.

## Starting State

- LibreOffice Calc opens with a CSV file containing library checkout data
- Data contains: Title, Type, Checkout Date, Library Branch, Renewals Used, Has Hold
- 15-18 books/DVDs from different branches with various checkout dates
- Some items may already be overdue, some due soon, others have time

## Required Actions

### 1. Calculate Due Dates
- Add "Due Date" column
- Use date arithmetic: `Checkout Date + Loan Period`
- Loan periods vary by branch:
  - **Main Library**: 21 days
  - **North Branch**: 14 days
  - **South Branch**: 14 days
- Use IF or VLOOKUP to determine loan period

### 2. Calculate Days Until Due
- Add "Days Until Due" column
- Formula: `Due Date - TODAY()`
- Negative values indicate overdue items

### 3. Determine Renewal Eligibility
- Add "Can Renew" column
- Logic: Can renew if BOTH:
  - Renewals Used < 3 (max 3 renewals allowed)
  - Has Hold = "No" (items with holds cannot be renewed)
- Use IF with AND logic

### 4. Calculate Potential Late Fees
- Add "Potential Late Fee (if 7 days late)" column
- Fee structure:
  - Books: $0.25 per day × 7 days = $1.75
  - DVDs: $1.00 per day × 7 days = $7.00
- Use IF based on Type

### 5. Assign Priority
- Add "Priority" column with urgency levels:
  - **"OVERDUE"**: Items with Days Until Due < 0
  - **"URGENT"**: Items due within 3 days (0 to 3 days)
  - **"HIGH"**: Items that cannot be renewed (and not urgent/overdue)
  - **"NORMAL"**: All other items
- Use nested IF or complex logic

### 6. Apply Conditional Formatting
- Highlight overdue items (Days Until Due < 0) with **red background**
- Highlight due within 3 days with **yellow background**
- Highlight "Can Renew = No" with **orange text** (optional)

### 7. Sort Data
- Multi-level sort:
  - Primary: Priority (OVERDUE → URGENT → HIGH → NORMAL)
  - Secondary: Days Until Due (ascending, most urgent first)

### 8. Save File
- Save as `/home/ga/Documents/library_organized.ods`

## Success Criteria

1. ✅ **Due Date Formulas**: Correct date arithmetic with branch-specific loan periods
2. ✅ **Days Until Due Calculation**: Uses TODAY() function properly
3. ✅ **Renewal Logic**: Accurate conditional logic (renewals < 3 AND no holds)
4. ✅ **Late Fee Calculation**: Correct fees by item type (Book: $1.75, DVD: $7.00)
5. ✅ **Priority Assignment**: Appropriate priority levels based on urgency
6. ✅ **Conditional Formatting**: Visual highlighting present
7. ✅ **Data Sorted**: Organized by priority and urgency

**Pass Threshold**: 70% (requires 5 out of 7 criteria)

## Skills Tested

- Date functions (DATE, TODAY, date arithmetic)
- Conditional logic (IF, AND, OR)
- Cell references (absolute and relative)
- Text functions
- Multi-criteria sorting
- Conditional formatting rules
- Formula creation and debugging
- Real-world problem solving under time pressure

## Loan Period Reference

| Branch | Loan Period |
|--------|-------------|
| Main Library | 21 days |
| North Branch | 14 days |
| South Branch | 14 days |

## Fee Structure

| Item Type | Fee per Day |
|-----------|-------------|
| Book | $0.25 |
| DVD | $1.00 |

## Example Priority Logic
