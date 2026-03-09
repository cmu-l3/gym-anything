# Validate CSV Transformation Task

**Difficulty**: 🟡 Easy-Medium  
**Skills**: Terminal usage, data validation, file comparison, diff viewer  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Run a data transformation script on sample CSV data and validate the output correctness using VSCode's diff viewer to compare against expected results.

## Scenario

You're a backend developer validating an ETL script (`parse_orders.py`) that transforms raw e-commerce order data into a normalized format. The QA team provided sample input and expected output files for validation before production deployment.

## Expected Workflow

1. Navigate to `/home/ga/workspace/data_validation/`
2. Open integrated terminal (Ctrl+`)
3. Run: `python parse_orders.py sample_input.csv actual_output.csv`
4. Use VSCode's diff viewer to compare files:
   - Right-click `actual_output.csv` → "Select for Compare"
   - Right-click `expected_output.csv` → "Compare with Selected"
5. Verify outputs match
6. Create `validation_passed.txt` with text: "Output matches expected result"

## Verification

Checks for:
1. `actual_output.csv` was generated (script executed)
2. Output content matches expected result exactly
3. Validation confirmation file created

**Pass Threshold**: 100% for complete validation, partial credit for execution only