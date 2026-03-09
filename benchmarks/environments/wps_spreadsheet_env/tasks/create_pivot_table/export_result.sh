#!/bin/bash
echo "=== Exporting task result ==="

DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

python3 << 'PYEOF'
import json
import os

result = {
    "file_exists": False,
    "sheets": [],
    "has_multiple_sheets": False,
    "error": None
}

files = [
    "/home/ga/Documents/employee_sales.xlsx",
    "/home/ga/Documents/pivot_table.xlsx",
    "/home/ga/Documents/Pivot.xlsx"
]

found_file = None
for f in files:
    if os.path.exists(f):
        found_file = f
        break

if found_file:
    result["file_exists"] = True

    try:
        from openpyxl import load_workbook
        wb = load_workbook(found_file)
        result["sheets"] = wb.sheetnames
        result["has_multiple_sheets"] = len(wb.sheetnames) > 1
    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

print(json.dumps(result, indent=2))

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
