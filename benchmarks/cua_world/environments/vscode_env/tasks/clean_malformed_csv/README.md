# VSCode Data Manipulation Task (`clean_malformed_csv@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, Python scripting, CSV handling, encoding management, integrated terminal  
**Duration**: 120 seconds  
**Steps**: ~30

## Objective

Clean a malformed CSV export file using VSCode and Python, producing a valid CSV with consistent structure.

## Starting State

- Workspace at `/home/ga/workspace/data_cleanup/`
- Malformed CSV: `customer_export_broken.csv` (50 rows with various issues)
- Empty script: `clean_data.py`
- Requirements file: `requirements.txt` (explains expected output format)

## CSV Issues Present

The input CSV has realistic data quality problems:
- **Mixed delimiters**: Some rows use semicolons instead of commas
- **Unescaped commas**: Description fields contain unquoted commas
- **Encoding problems**: UTF-8 characters (é, ñ, ö) may appear as mojibake
- **Inconsistent columns**: Some rows have 3-7 columns instead of 5
- **Extra whitespace**: Leading/trailing spaces in fields

## Expected Workflow

1. Open and inspect `customer_export_broken.csv` to understand issues
2. Read `requirements.txt` to understand output specifications
3. Write a Python script in `clean_data.py` that:
   - Reads the broken CSV with proper error handling
   - Normalizes delimiters, quoting, and encoding
   - Filters or fixes rows with wrong column counts
   - Writes cleaned data to `customer_export_clean.csv`
4. Open integrated terminal (`Ctrl+Shift+\``)
5. Run: `python clean_data.py`
6. Verify output by opening the cleaned CSV file
7. Re-run if needed to fix issues

## Verification

Checks for:
1. ✅ Output file `customer_export_clean.csv` exists
2. ✅ Output is valid CSV (parseable with Python csv module)
3. ✅ All rows have exactly 5 columns
4. ✅ UTF-8 encoding is correct (no mojibake)
5. ✅ Reasonable data retention (≥80% of input rows)
6. ✅ Script shows CSV-aware parsing (imports csv module)

**Pass Threshold**: 75% (4/6 criteria)

## Real-World Context

You're migrating customer data from a legacy system. The IT department provided a CSV export, but it's malformed—mixed delimiters, encoding issues, inconsistent structure. Your database import tool is strict and will reject this file. You need to clean it quickly so the migration can proceed.

## Learning Outcomes

- Handle real-world data quality issues
- Use Python's `csv` module for robust parsing
- Manage UTF-8 encoding explicitly
- Write error-tolerant data processing scripts
- Use VSCode's integrated terminal for iterative development
- Validate output data quality

## Tips

- Use `csv.DictReader` or `csv.reader` with error handling
- Specify `encoding='utf-8'` when opening files
- Handle rows with wrong column counts gracefully
- Test script output before considering task complete