# Bank Transaction Import Formatter Task

**Difficulty**: 🟡 Medium  
**Skills**: Data transformation, format compliance, CSV export, date formatting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Transform a messy bank transaction export into a specific CSV format required by budgeting software. This task tests data transformation, format specification compliance, and handling real-world data messiness.

## Task Description

You receive a bank export file with a messy structure:
- Merged header cells with bank name
- Export timestamp row
- Non-standard column names
- Dates in MM/DD/YYYY format (need YYYY-MM-DD)
- Separate Debit/Credit columns (need single Amount column)
- Extra columns: Balance, Account Number, Check Number
- Footer row with transaction count

Your budgeting software requires **exact** format: