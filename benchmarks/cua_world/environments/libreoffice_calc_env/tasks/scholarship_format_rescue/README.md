# Scholarship Financial Data Formatter Task

**Difficulty**: 🟡 Medium  
**Skills**: Data type conversion, format standardization, category mapping, formula creation  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~15

## Objective

Transform messy financial data from a university financial aid export into the exact format required by a scholarship application portal. The portal has strict format requirements and will auto-reject improperly formatted submissions. This task tests data cleanup, format conversion, category mapping, and attention to specification details.

## Task Description

**Scenario**: A student discovers 48 hours before a scholarship deadline that their financial aid office export doesn't match the required format. They need to transform the data to meet exact specifications.

The agent must:
1. Open the messy source data file (`financial_aid_export.ods`)
2. Review the requirements document (`scholarship_requirements.txt`)
3. Standardize date formats to YYYY-MM-DD
4. Convert text-formatted numbers to proper numeric values
5. Fix negative number formatting from "(1234)" to "-1234"
6. Map expense categories to required taxonomy
7. Calculate derived fields (Monthly_Amount, Semester_Total, Needs_Based)
8. Add missing required columns
9. Remove internal-use columns not allowed in submission
10. Rename and reorder columns to match specification exactly
11. Export as CSV with exact filename: `financial_data_submission.csv`

## Source Data Issues

The `financial_aid_export.ods` file contains:
- **Inconsistent dates**: Mix of "03/15/2024", "15-Mar-24", "March 15, 2024"
- **Text-formatted numbers**: Some amounts stored as text
- **Wrong negative format**: "(1,500.00)" instead of "-1500.00"
- **Category mismatches**: "Books" vs "Educational Materials", "Room & Board" vs "Housing"
- **Missing columns**: Monthly_Amount, Semester_Total, Needs_Based
- **Extra columns**: Internal_Code, Process_Date should be removed
- **Wrong order**: Columns scrambled, not in required sequence

## Required Output Format

**Filename**: `financial_data_submission.csv`  
**Format**: CSV (UTF-8, comma-delimited)

**Required Columns (exact order)**:
1. `Transaction_ID` (text, unique)
2. `Date` (text, YYYY-MM-DD format)
3. `Category` (text, from taxonomy)
4. `Description` (text)
5. `Amount` (number, 2 decimal places)
6. `Monthly_Amount` (number, = Amount/12)
7. `Semester_Total` (number, = Monthly_Amount*4)
8. `Needs_Based` (text, "Yes" if Source is "Grant" or "Scholarship", else "No")
9. `Source` (text, one of: Loan, Grant, Scholarship, Work-Study, Personal)

**Category Taxonomy**: Tuition, Housing, Educational Materials, Transportation, Healthcare, Miscellaneous

## Verification Criteria

1. ✅ **Structure Correct**: 9 columns in specified order with exact names (15 pts)
2. ✅ **Dates Valid**: All dates in YYYY-MM-DD format within academic year (20 pts)
3. ✅ **Numbers Clean**: Numeric columns properly formatted, no text (20 pts)
4. ✅ **Categories Mapped**: All categories match required taxonomy (15 pts)
5. ✅ **Calculations Accurate**: Derived fields correctly calculated (20 pts)
6. ✅ **No Missing Data**: All required fields populated (10 pts)

**Pass Threshold**: 85 points (scholarship portals auto-reject anything less than perfect)

## Skills Tested

- Specification reading and compliance
- Date format standardization
- Data type conversion (text to numbers)
- Find & Replace operations
- Formula creation (calculated fields)
- Conditional logic (IF statements or VLOOKUP)
- Column management (insert, delete, rename, reorder)
- CSV export with specific settings
- Quality validation

## Tips

- Read `scholarship_requirements.txt` carefully for exact specifications
- Work systematically through each requirement
- Use Find & Replace for bulk date/number corrections
- Create formulas for derived fields rather than hardcoding
- Verify column names are case-sensitive matches
- Check that CSV export uses comma delimiter, UTF-8 encoding
- Final validation: ensure no empty cells in required fields