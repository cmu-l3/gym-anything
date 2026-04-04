#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# Check for spreadsheet files
RESULT_FILE="/tmp/task_result.json"

# Check for summary sheet with formulas
python3 << 'PYEOF'
import json
import os
import sys
from pathlib import Path

result = {
    "found_summary": False,
    "has_formulas": False,
    "sheets": [],
    "error": None
}

# Check for the original data file
data_file = "/home/ga/Documents/sales_data.xlsx"
summary_file = None

# Find the summary file - could be same file with new sheet or a new file
for f in ["/home/ga/Documents/sales_data.xlsx", "/home/ga/Documents/sales_summary.xlsx", "/home/ga/Documents/Summary.xlsx"]:
    if os.path.exists(f):
        summary_file = f
        break

if summary_file and os.path.exists(summary_file):
    result["found_summary"] = True
    result["file_found"] = summary_file

    try:
        from openpyxl import load_workbook

        wb = load_workbook(summary_file, data_only=False)
        result["sheets"] = wb.sheetnames

        # Check for formulas
        formula_count = 0
        for sheet_name in wb.sheetnames:
            sheet = wb[sheet_name]
            for row in sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                        formula_count += 1

        result["formula_count"] = formula_count
        result["has_formulas"] = formula_count > 0

    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "No spreadsheet file found"

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

print(json.dumps(result, indent=2))

PYEOF

# Make result readable
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
