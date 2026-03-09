#!/bin/bash
echo "=== Exporting production_capacity_planning result ==="

DISPLAY=:1 import -window root /tmp/production_capacity_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/production_capacity_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/production_capacity_start_ts 2>/dev/null || echo "0")

python3 << 'PYEOF'
import json
import os

result = {
    "file_exists": False,
    "file_is_new": False,
    "sheets": [],
    "has_schedule_sheet": False,
    "has_utilization_sheet": False,
    "has_revenue_sheet": False,
    "new_sheet_count": 0,
    "formula_count": 0,
    "has_conditional_formatting": False,
    "has_chart": False,
    "error": None
}

task_start = int(open('/tmp/production_capacity_start_ts').read().strip()) if os.path.exists('/tmp/production_capacity_start_ts') else 0

candidates = ["/home/ga/Documents/production_capacity_plan.xlsx"]
docs_dir = "/home/ga/Documents/"
if os.path.isdir(docs_dir):
    for f in os.listdir(docs_dir):
        if f.endswith(('.xlsx', '.xls', '.et')) and ('production' in f.lower() or 'capacity' in f.lower()):
            candidates.append(os.path.join(docs_dir, f))

found_file = None
for cf in candidates:
    if os.path.exists(cf):
        found_file = cf
        break

if found_file:
    result["file_exists"] = True
    result["found_path"] = found_file
    mtime = int(os.path.getmtime(found_file))
    result["file_is_new"] = mtime > task_start

    try:
        from openpyxl import load_workbook
        wb = load_workbook(found_file, data_only=False)
        result["sheets"] = wb.sheetnames

        starter = {"Production_Lines", "Orders", "Calendar"}
        new_sheets = [s for s in wb.sheetnames if s not in starter]
        result["new_sheet_count"] = len(new_sheets)

        result["has_schedule_sheet"] = any('schedule' in s.lower() or 'alloc' in s.lower() for s in wb.sheetnames)
        result["has_utilization_sheet"] = any('utiliz' in s.lower() or 'capacity' in s.lower() for s in wb.sheetnames)
        result["has_revenue_sheet"] = any('revenue' in s.lower() or 'profit' in s.lower() or 'cost' in s.lower() for s in wb.sheetnames)

        formula_count = 0
        for sn in new_sheets:
            sheet = wb[sn]
            for row in sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                        formula_count += 1
        result["formula_count"] = formula_count

        for sn in wb.sheetnames:
            sheet = wb[sn]
            if sheet.conditional_formatting:
                result["has_conditional_formatting"] = True
                break

        for sn in wb.sheetnames:
            sheet = wb[sn]
            if hasattr(sheet, '_charts') and len(sheet._charts) > 0:
                result["has_chart"] = True
                break

    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "No production workbook found"

result["task_start"] = task_start

with open("/tmp/production_capacity_result.json", "w") as f:
    json.dump(result, f)
print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/production_capacity_result.json 2>/dev/null || true
echo "=== Export complete ==="
