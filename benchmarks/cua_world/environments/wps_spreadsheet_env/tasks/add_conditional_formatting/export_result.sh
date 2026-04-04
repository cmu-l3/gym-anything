#!/bin/bash
echo "=== Exporting task result ==="

DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

python3 << 'PYEOF'
import json
import os

result = {
    "file_exists": False,
    "has_conditional_formatting": False,
    "cf_rules_count": 0,
    "sheets": [],
    "error": None
}

inventory_file = "/home/ga/Documents/inventory.xlsx"

if os.path.exists(inventory_file):
    result["file_exists"] = True

    try:
        from openpyxl import load_workbook

        wb = load_workbook(inventory_file)
        result["sheets"] = wb.sheetnames

        sheet = wb.active
        if hasattr(sheet, 'conditional_formatting'):
            cf = sheet.conditional_formatting
            result["cf_rules_count"] = len(cf._cf_rules) if cf._cf_rules else 0
            result["has_conditional_formatting"] = result["cf_rules_count"] > 0

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
