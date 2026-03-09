# Validate Data Pipeline Task

**Difficulty**: 🟡 Medium  
**Skills**: Data inspection, test creation, debugging, validation, documentation  
**Duration**: 900 seconds  
**Steps**: ~100

## Objective

Validate a data transformation pipeline that converts CSV order data to JSON reports. The task simulates inheriting data processing code that needs verification.

## Scenario

A colleague wrote a data processing script (`process_orders.py`) that transforms customer order data from CSV format into a JSON report. You're getting reports that some orders are being processed incorrectly. Your job is to validate the transformation works correctly by creating test data and examining the results.

## Expected Workflow

1. Examine the existing transformation function in `process_orders.py`
2. Create a test CSV file (`orders.csv`) with at least 3 sample orders
3. Include at least one edge case in your test data
4. Run the transformation script to generate `report.json`
5. Inspect the output and validate correctness
6. Add validation logic (assertions, logging, or comments) to the code
7. Document your findings in `VALIDATION.md`

## Test Data Format

The CSV should follow this format: