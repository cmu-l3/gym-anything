# Raffle Ticket Validator Task

**Difficulty**: 🟡 Medium  
**Skills**: Data validation, text parsing, conditional logic, duplicate detection, formula creation  
**Duration**: 240 seconds  
**Steps**: ~30

## Objective

Clean and validate messy fundraising data by identifying duplicate raffle tickets, calculating accurate seller totals, flagging suspicious entries, and preparing a validated ticket list for a community drawing. This simulates real-world volunteer data collection challenges.

## Task Description

A community organization held a raffle fundraiser where 12 volunteer sellers sold tickets numbered 0001-0500. Each seller submitted their sales data, but the spreadsheet has issues:
- **Inconsistent formats**: Some used ranges ("0100-0125"), others individual numbers ("0067")
- **Duplicates**: Some tickets were accidentally sold twice
- **Data entry errors**: Impossible ranges, missing data
- **Validation needed**: The drawing is tomorrow and all tickets must be verified!

The agent must:
1. Parse ticket range notation (e.g., "0100-0125" represents 26 tickets)
2. Calculate correct ticket counts per seller
3. Identify and flag duplicate tickets across all submissions
4. Flag impossible or suspicious ranges
5. Identify top 3 sellers by verified ticket count
6. Calculate total verified tickets eligible for drawing

## Starting Data Structure

CSV with columns:
- **Seller Name**: Volunteer's name
- **Tickets Sold**: Text field with ranges ("0100-0125"), individual ("0067"), or mixed ("0050, 0051-0055")
- **Money Collected**: Dollar amount
- **Date Submitted**: Submission date

## Intentional Data Issues

1. **Martinez** (Row 4): Has ticket "0067" which overlaps with Johnson's range "0050-0075"
2. **Chen** (Rows 5 & 10): Submitted data twice with identical range "0300-0324"
3. **Davis** (Row 9): Money collected but no ticket numbers (missing data)
4. **Lee** (Row 11): Impossible range "0350-0295" (end before start)
5. **Garcia** (Row 12): Range "0400-0455" is suspicious (56 tickets from one person)

## Required Actions

### Phase 1: Count Calculation
1. Add "Ticket Count" column
2. Create formulas to parse ticket ranges:
   - "0100-0125" → 26 tickets (inclusive: 125-100+1)
   - "0001-0050" → 50 tickets
   - "0045" → 1 ticket
   - "0010, 0011-0015, 0020" → 7 tickets (mixed format)

### Phase 2: Duplicate Detection
3. Add "Duplicate Flag" column
4. Identify overlapping tickets:
   - Individual tickets appearing multiple times
   - Overlapping ranges
   - Tickets in both individual entries and ranges
5. Mark duplicates with "DUPLICATE" or use conditional formatting (red)

### Phase 3: Validation
6. Add "Validation Status" column
7. Flag issues:
   - Ranges where end < start (e.g., "0350-0295")
   - Unusually large ranges (>100 tickets)
   - Missing ticket data when money was collected

### Phase 4: Ranking
8. Add "Verified Ticket Count" column (excludes duplicates/invalid)
9. Add "Top Seller" column
10. Identify and mark top 3 sellers by verified count

### Phase 5: Summary
11. Create summary cell with "Total Verified Tickets"
12. Calculate final count (should be ~387 tickets after removing 45 duplicates and 18 invalid)

## Success Criteria

1. ✅ **Duplicate Detection**: Column exists and correctly identifies at least 4 known duplicates
2. ✅ **Count Accuracy**: At least 8 of 10 tested calculations correct (±1 tolerance)
3. ✅ **Validation Flags**: At least 3 of 4 known invalid entries flagged
4. ✅ **Top Sellers Identified**: Correct top 3 sellers marked (Rodriguez, Patel, O'Brien)
5. ✅ **Final Total Correct**: Verified total is 387 ± 5 tickets

**Pass Threshold**: 70% (requires at least 3 out of 5 criteria)

## Skills Tested

- **Text parsing functions**: FIND, MID, LEFT, RIGHT, VALUE
- **Conditional logic**: IF, AND, OR, NOT, COUNTIF
- **Range expansion**: Understanding inclusive counting
- **Duplicate detection**: Cross-referencing across formats
- **Data validation**: Logical impossibility detection
- **Ranking functions**: RANK, LARGE
- **Formula composition**: Nested functions

## Expected Final Results

### Top 3 Sellers (by verified tickets):
1. **Rodriguez**: 78 tickets (0001-0078)
2. **Patel**: 65 tickets (0079-0099, 0150-0193)
3. **O'Brien**: 52 tickets (0200-0251)

### Total Verified Tickets: 387
- Original claims: ~450 tickets
- Duplicates removed: 45 tickets
- Invalid entries: 18 tickets
- Final verified: 387 tickets

## Tips

- Use FIND() or SEARCH() to detect "-" in range notation
- LEFT() and RIGHT() extract start/end numbers
- VALUE() converts text to numbers
- For inclusive counting: END - START + 1
- COUNTIF can detect if a value appears multiple times
- Conditional formatting makes issues visually obvious
- Use mixed absolute/relative references ($A$2 vs A2)