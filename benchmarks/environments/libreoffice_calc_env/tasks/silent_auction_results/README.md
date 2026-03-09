# LibreOffice Calc Silent Auction Winner Determination Task (`silent_auction_results@1`)

## Overview

This task tests an agent's ability to process messy auction data, determine winners, calculate totals, and generate a payment summary. The agent must work with realistic data entry inconsistencies, apply conditional logic to determine winners based on bidding rules, and create a clean summary for auction organizers to collect payments and distribute items.

## Rationale

**Why this task is valuable:**
- **Data Cleaning Skills:** Tests ability to work with inconsistent real-world data entry (currency formatting, missing values)
- **Conditional Logic Mastery:** Requires IF statements and logical operations to determine winners and handle edge cases
- **Multi-criteria Decision Making:** Must consider reserve prices, bid validity, and tie-breaking rules
- **Practical Workflow Simulation:** Mimics real charity auction, school fundraiser, or community event scenario
- **Real-world Time Pressure:** Reflects actual time-sensitive situation where people are waiting for results
- **Formula Combination:** Integrates MAX, IF, VLOOKUP, and COUNTIF functions in practical business context
- **Edge Case Handling:** Forces proper treatment of no bids, failed reserve prices, and data inconsistencies

**Skill Progression:** This task bridges data cleaning with business logic application, requiring both technical formula skills and understanding of real-world auction rules.

## Skills Required

### A. Interaction Skills
- **Data Navigation:** Scroll and examine multi-column datasets with varying data quality
- **Formula Entry:** Type complex nested formulas with proper syntax and parentheses
- **Cell Formatting:** Apply currency, text, and conditional formatting appropriately
- **Column Manipulation:** Insert new columns for calculated results
- **Range Selection:** Select appropriate cell ranges for formulas
- **Data Validation:** Identify and handle inconsistent data entries visually

### B. LibreOffice Calc Knowledge
- **Formula Functions:** Master MAX, IF, COUNTIF, INDEX/MATCH or nested IF logic
- **Cell References:** Use absolute ($) and relative references correctly in formulas
- **Data Type Conversion:** Understand and convert between text and numeric formats
- **Conditional Logic:** Implement multi-condition formulas (reserve prices, minimum bids)
- **Sorting and Filtering:** Organize results by winner, amount, or item category
- **String Functions:** Use VALUE() or similar to clean currency text
- **Error Handling:** Use IFERROR or conditional logic to handle division by zero, missing data

### C. Task-Specific Skills
- **Auction Rules Understanding:** Know that highest bid wins, reserve prices must be met
- **Edge Case Recognition:** Identify and handle no bids, tied bids, failed reserve prices
- **Business Context Awareness:** Understand why certain calculations matter (payment collection, item distribution)
- **Data Quality Assessment:** Identify problematic entries and decide on reasonable interpretations
- **Summary Creation:** Generate actionable totals and counts for event organizers
- **Payment Collection Logic:** Create clear "amount owed" column for winners

## Starting Data Structure

The spreadsheet opens with **20 auction items** in columns A-N:

| Column | Content | Notes |
|--------|---------|-------|
| A | Item ID | 1-20 |
| B | Item Name | e.g., "Vintage Wine Basket" |
| C | Starting Bid | Minimum bid to open |
| D | Reserve Price | Minimum to sell item |
| E | Bid 1 | First bid amount (some with "$") |
| F | Bidder 1 | First bidder ID (e.g., "B042") |
| G | Bid 2 | Second bid amount |
| H | Bidder 2 | Second bidder ID |
| I | Bid 3 | Third bid amount |
| J | Bidder 3 | Third bidder ID |
| K | Bid 4 | Fourth bid amount |
| L | Bidder 4 | Fourth bidder ID |
| M | Bid 5 | Fifth bid amount |
| N | Bidder 5 | Fifth bidder ID |

**Data Messiness (Realistic):**
- Some bid amounts stored as text with "$" symbol (e.g., "$110")
- Some bid amounts stored as plain numbers (e.g., 250)
- Empty cells where bids weren't submitted
- 2-3 items with NO bids at all
- 3-4 items where highest bid is below reserve price
- Most items have successful sales

## Required Actions

### Step 1: Create Highest Bid Column (Column O)
- Add header "Highest Bid" in O1
- Enter MAX formula in O2 to find highest value across columns E, G, I, K, M
- Example formula: `=MAX(E2,G2,I2,K2,M2)` or handle text: `=MAX(VALUE(E2),VALUE(G2),VALUE(I2),VALUE(K2),VALUE(M2))`
- Copy formula down to row 21

### Step 2: Create Winning Bidder Column (Column P)
- Add header "Winning Bidder" in P1
- Enter nested IF or INDEX/MATCH formula to find which bidder made the highest bid
- Example logic: `=IF(O2=0,"",IF(E2=O2,F2,IF(G2=O2,H2,IF(I2=O2,J2,IF(K2=O2,L2,IF(M2=O2,N2,""))))))`
- Handle empty cells and $-formatted text appropriately
- Copy formula down to row 21

### Step 3: Create Sale Status Column (Column Q)
- Add header "Sale Status" in Q1
- Enter formula to check if highest bid meets reserve price
- Logic: `=IF(O2=0,"NO BIDS",IF(O2>=D2,"SOLD","NOT SOLD"))`
- Copy formula down to row 21

### Step 4: Create Final Price Column (Column R)
- Add header "Final Price" in R1
- Enter formula: only show price if item SOLD
- Logic: `=IF(Q2="SOLD",O2,0)` or `=IF(Q2="SOLD",O2,"")`
- Copy formula down to row 21

### Step 5: Create Summary Statistics
In a clear area below the data (e.g., rows 23-27), create:

1. **Total Revenue Raised:** `=SUM(R2:R21)`
2. **Items Successfully Sold:** `=COUNTIF(Q2:Q21,"SOLD")`
3. **Items Not Sold:** `=COUNTIF(Q2:Q21,"NOT SOLD")+COUNTIF(Q2:Q21,"NO BIDS")`
4. **Highest Sale Price:** `=MAX(R2:R21)`

### Step 6: Optional Formatting
- Apply currency formatting to columns O and R
- Apply conditional formatting to highlight SOLD (green), NOT SOLD (red)
- Bold summary statistics

### Step 7: Save
- Save the file (Ctrl+S)

## Success Criteria

### Verification Checklist
1. ✅ **Highest Bid Calculated:** Column O contains correct maximum bid for each item (≥95% accuracy)
2. ✅ **Winners Determined:** Column P correctly identifies winning bidder (≥90% accuracy)
3. ✅ **Reserve Price Logic:** Column Q correctly applies SOLD/NOT SOLD/NO BIDS rules (≥95% accuracy)
4. ✅ **Revenue Calculated:** Column R and total revenue match expected values (within $1.00 tolerance)
5. ✅ **Required Columns Present:** All four columns (O, P, Q, R) exist and populated
6. ✅ **Summary Statistics:** At least 2 of 4 summary calculations present and correct

### Scoring System
- **100%:** All 6 criteria met perfectly
- **85-99%:** 5/6 criteria met (minor errors)
- **70-84%:** 4/6 criteria met (core logic correct)
- **50-69%:** 3/6 criteria met (partial completion)
- **0-49%:** <3 criteria met (incomplete)

**Pass Threshold:** 70% (requires at least 4 out of 6 criteria)

## Real-world Scenario Context

**Event:** Community Center Annual Silent Auction Fundraiser  
**When:** Saturday evening, auction just closed at 8 PM  
**Who:** Volunteer coordinator using donated laptop with LibreOffice  
**Pressure:** 50+ attendees waiting in the hall for results announcement  
**Problem:** Paper bid sheets were transcribed hastily, data is messy  
**Urgency:** Need to announce winners, collect payments, distribute items within 30 minutes  
**Stakes:** Revenue supports youth programs; board president wants final number for speech

## Tips for Agents

- **Handle text-formatted numbers:** Use VALUE() function or conditional logic
- **Empty cells:** MAX function ignores empty cells automatically
- **Bidder lookup:** Use nested IFs or INDEX/MATCH to find winner
- **Reserve price check:** Simple IF statement comparing highest bid to reserve
- **Summary functions:** Use SUM, COUNTIF, MAX for statistics
- **Double-check edge cases:** Items with no bids, items below reserve

## Difficulty: 🟡 Medium

**Estimated Time:** 5 minutes  
**Estimated Steps:** 25  
**Key Challenge:** Handling messy real-world data with conditional logic

---

*This task authentically captures the intersection of data manipulation skills, business logic implementation, and real-world problem-solving that makes spreadsheet competency valuable!*