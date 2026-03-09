#!/bin/bash
echo "=== Exporting task result ==="

DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

python3 << 'PYEOF'
import json
import os

result = {
    "file_exists": False,
    "has_data_validation": False,
    "dv_count": 0,
    "has_freeze_panes": False,
    "sheets": [],
    "error": None
}

project_file = "/home/ga/Documents/project_tracker.xlsx"

if os.path.exists(project_file):
    result["file_exists"] = True

    try:
        from openpyxl import load_workbook
        wb = load_workbook(project_file)
        result["sheets"] = wb.sheetnames

        sheet = wb.active

        # Check for data validation
        if hasattr(sheet, 'data_validations'):
            dv = sheet.data_validations
            result["dv_count"] = len(dv.dataValidation) if dv.dataValidation else 0
            result["has_data_validation"] = result["dv_count"] > 0

        # Check for freeze panes
        if sheet.freeze_panes:
            result["has_freeze_panes"] = True

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
