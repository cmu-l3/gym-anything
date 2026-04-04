# LibreOffice Calc Charity Silent Auction Bid Sheet Task (`charity_silent_auction@1`)

## Overview

This task tests an agent's ability to organize and manage a charity silent auction's bid tracking spreadsheet during an active event. The agent receives a partially-completed auction spreadsheet with item donations and bids already entered, but needs to: (1) determine current winning bids for each item, (2) validate that bid increments follow the minimum raise rules, (3) calculate total raised funds, and (4) identify which items have received no bids and may need price adjustments. This simulates the real-world pressure of managing a fundraising event where data entry is messy and the volunteer coordinator needs quick answers.

## Rationale

**Why this task is valuable:**
- **Multi-criteria Analysis:** Requires understanding business rules (minimum bid increments), time-based logic (latest valid bid), and data validation
- **Real-time Event Management:** Simulates pressure of live event where quick, accurate analysis is needed
- **Messy Real-world Data:** Includes realistic auction scenarios (no bids, below reserve, competitive bidding)
- **Conditional Logic Mastery:** Must use IF statements and comparison operators to determine winning bids
- **Practical Nonprofit Skills:** Directly applicable to fundraising events, raffles, and charity auctions
- **Formula Combination:** Requires MAXIFS, COUNTIF, VLOOKUP, and conditional formulas working together

## Task Description

**Difficulty:** 🟡 Medium  
**Estimated Steps:** 50  
**Timeout:** 300 seconds (5 minutes)

### Starting State

- LibreOffice Calc opens with a multi-sheet workbook (`auction_tracker.ods`)
- **Items sheet:** 10 auction items with starting bids and reserve prices
- **Bids sheet:** 25+ bids placed by various bidders (some items have no bids)
- **Bidders sheet:** 18 registered bidders with contact information
- **Summary sheet:** Template with headers and pre-filled item information

### Required Actions

1. **Identify Current Highest Bid Per Item (Column E)**
   - Use MAXIFS or similar to find the maximum bid amount for each item from Bids sheet
   - Handle items with zero bids (return 0 or leave empty)

2. **Determine Winning Bidder Number (Column F)**
   - Identify the bidder who placed the highest bid for each item
   - Can use INDEX/MATCH or array formulas

3. **Look Up Winning Bidder Name (Column G)**
   - Use VLOOKUP or INDEX/MATCH to get bidder name from Bidders sheet
   - Handle items with no bids gracefully

4. **Determine Item Status (Column H)**
   - Use IF logic to determine: "SOLD", "BELOW RESERVE", or "NO BIDS"
   - SOLD: high bid ≥ reserve price
   - BELOW RESERVE: has bids but highest < reserve price
   - NO BIDS: no bids received

5. **Validate Bid Increments (Column I - Optional)**
   - Check if high bid meets minimum increment rules:
     - Starting bid $0-$49: minimum $5 raise
     - Starting bid $50-$199: minimum $10 raise
     - Starting bid $200+: minimum $25 raise

6. **Calculate Total Revenue**
   - Sum all winning bids where status = "SOLD"
   - Place in totals section (around row 17-18)

7. **Count Items Sold**
   - Count items with status = "SOLD"

8. **Count Items Needing Attention**
   - Count items with status = "NO BIDS" or "BELOW RESERVE"

## Success Criteria

1. ✅ **Winning Bids Identified:** Current high bid correctly calculated for all items (using formulas)
2. ✅ **Status Accurate:** All items have correct status (SOLD/BELOW RESERVE/NO BIDS)
3. ✅ **Revenue Calculated:** Total revenue correctly sums only SOLD items
4. ✅ **Problem Items Flagged:** Count of items needing attention is correct
5. ✅ **Lookups Work:** Winning bidder names correctly retrieved from Bidders sheet
6. ✅ **Business Rules Applied:** Bid increment validation implemented (bonus)

**Pass Threshold:** 80% (5 out of 6 criteria, or 4 out of 5 if increment validation skipped)

## Skills Tested

- **Multi-sheet References:** Referencing data across Items, Bids, and Bidders sheets
- **Conditional Formulas:** IF, IFS for status determination
- **Lookup Functions:** VLOOKUP, INDEX/MATCH for bidder information
- **Aggregate Functions:** MAXIFS, SUMIF, COUNTIF for analysis
- **Business Logic:** Implementing complex rules (bid increments, reserve prices)
- **Data Validation:** Handling edge cases (no bids, ties, missing data)

## Expected Data Scenarios

The auction includes realistic scenarios:
- **Successful items:** Multiple competitive bids, sold above reserve
- **Below reserve items:** Bids received but below minimum acceptable price
- **No bids items:** Expensive items or less popular items with zero bids
- **Exact reserve:** Items where highest bid exactly meets reserve price
- **Last-minute bids:** Items with bids placed near end of auction

## Business Rules

### Minimum Bid Increments
- **$0 - $49 starting bid:** Minimum $5 raise
- **$50 - $199 starting bid:** Minimum $10 raise
- **$200+ starting bid:** Minimum $25 raise

### Item Status
- **SOLD:** High bid ≥ reserve price
- **BELOW RESERVE:** Has bids but high bid < reserve price
- **NO BIDS:** No bids received

## Tips

- Start with simpler formulas (high bid, status) before complex lookups
- Use MAXIFS(Bids.D:D, Bids.B:B, A4) to find max bid for item in A4
- COUNTIF and SUMIF are useful for the totals section
- VLOOKUP syntax: =VLOOKUP(F4, Bidders.A:B, 2, FALSE)
- Test formulas on first row, then copy down to other items

## Sample Formulas
