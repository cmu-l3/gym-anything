# Legacy POS System Data Rescue Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, deduplication, formulas, customer analytics  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~15

## Objective

Rescue and clean customer transaction data from a dying point-of-sale system. The exported CSV file is messy with duplicate customers, inconsistent formatting, and mixed date/currency formats. Clean the data, identify VIP customers, and prepare it for import into a new system.

## Task Description

A small retail business is migrating from an old POS system being discontinued. You have one week to clean 3 years of customer transaction history. The data has realistic problems:

- **Duplicate customers**: Same person with name variations ("John Smith", "J. Smith", "Smith, John")
- **Date format chaos**: MM/DD/YYYY, DD-MM-YY, YYYY-MM-DD mixed together
- **Currency inconsistency**: "$45.99", "67.50 USD", "23.75" mixed formats
- **Whitespace issues**: Leading/trailing spaces, inconsistent capitalization

The agent must:
1. Import the messy CSV file (`old_pos_export.csv`)
2. Standardize customer names (Title Case, trimmed)
3. Consolidate duplicate customer records
4. Standardize all dates to YYYY-MM-DD format
5. Clean currency values (numeric only, no symbols)
6. Calculate Customer Lifetime Value (total spending per customer)
7. Identify VIP customers (top 20% by spending using 80th percentile)
8. Create final output with required columns
9. Save as `cleaned_customer_data.csv`

## Expected Results

Final CSV should contain:
- **CustomerID**: Unique sequential ID per customer
- **CleanedName**: Standardized name (Title Case, no extra spaces)
- **TransactionDate**: YYYY-MM-DD format
- **CleanAmount**: Numeric value (no currency symbols)
- **VIP_Status**: "VIP" for top 20%, "Regular" otherwise
- **PaymentMethod**: Original payment method

## Verification Criteria

1. ✅ **Duplicates Removed**: 8-15 duplicate customers eliminated
2. ✅ **Names Standardized**: All names in Title Case, no leading/trailing spaces
3. ✅ **Dates Uniform**: All dates in YYYY-MM-DD format
4. ✅ **Amounts Clean**: All monetary values numeric (no text)
5. ✅ **CLV Calculated**: Customer lifetime value correctly computed
6. ✅ **VIP Logic Correct**: Top 20% by spending flagged as VIP
7. ✅ **Export Format Met**: Required columns present in correct order
8. ✅ **Data Preserved**: Total revenue matches original (±1% tolerance)

**Pass Threshold**: 75% (6/8 criteria must pass)

## Skills Tested

- CSV import and parsing
- Data cleaning with text functions (TRIM, PROPER, UPPER)
- Date standardization (DATE, TEXT functions)
- Duplicate detection and consolidation
- Aggregation formulas (SUMIF, COUNTIF)
- Statistical functions (PERCENTILE)
- Conditional logic (IF statements)
- Business metrics understanding (CLV, customer segmentation)

## Business Context

Maria owns a coffee shop using "RetailPro Classic" since 2019. The vendor just announced server shutdown in one week. She exported customer data but it's messy—duplicate entries because the system allowed creating new profiles instead of searching first. She needs to identify her VIP customers for a personal invitation to the grand reopening with the new system. She has one evening to fix this before her consultant imports everything tomorrow morning.

## Tips

- Use TRIM() and PROPER() for name cleaning
- TEXT() function can help standardize dates
- SUBSTITUTE() removes unwanted characters from currency
- SUMIF() calculates total spending per customer
- PERCENTILE() finds the 80th percentile threshold for VIP status
- Consider creating helper columns for intermediate calculations
- Sort final data by CustomerID for clean import