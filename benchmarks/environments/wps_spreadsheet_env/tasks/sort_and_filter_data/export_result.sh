#!/bin/bash
echo "=== Exporting task result ==="

DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

python3 << 'PYEOF'
import json
import os

result = {
    "file_exists": False,
    "has_filter": False,
    "has_freeze_panes": False,
    "is_sorted": False,
    "sheets": [],
    "error": None
}

orders_file = "/home/ga/Documents/customer_orders.xlsx"

if os.path.exists(orders_file):
    result["file_exists"] = True

    try:
        from openpyxl import load_workbook
        wb = load_workbook(orders_file)
        result["sheets"] = wb.sheetnames

        sheet = wb.active

        # Check for autoFilter
        if sheet.auto_filter and sheet.auto_filter.ref:
            result["has_filter"] = True

        # Check for freeze panes
        if sheet.freeze_panes:
            result["has_freeze_panes"] = True

        # Check if sorted (check Amount column for descending)
        amounts = []
        for row in sheet.iter_rows(min_row=2, min_col=8, max_col=8, values_only=True):
            if row[0] is not None:
                amounts.append(row[0])

        if len(amounts) > 1:
            result["is_sorted"] = amounts == sorted(amounts, reverse=True)

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
