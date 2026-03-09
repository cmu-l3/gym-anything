#!/bin/bash
echo "=== Exporting budget_variance_dashboard result ==="

DISPLAY=:1 import -window root /tmp/budget_variance_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/budget_variance_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/budget_variance_start_ts 2>/dev/null || echo "0")

python3 << 'PYEOF'
import json
import os

result = {
    "file_exists": False,
    "file_is_new": False,
    "sheets": [],
    "has_variance_sheet": False,
    "has_ytd_sheet": False,
    "has_executive_sheet": False,
    "new_sheet_count": 0,
    "formula_count": 0,
    "has_conditional_formatting": False,
    "has_chart": False,
    "chart_count": 0,
    "error": None
}

task_start = int(open('/tmp/budget_variance_start_ts').read().strip()) if os.path.exists('/tmp/budget_variance_start_ts') else 0

candidates = ["/home/ga/Documents/budget_variance_analysis.xlsx"]
docs_dir = "/home/ga/Documents/"
if os.path.isdir(docs_dir):
    for f in os.listdir(docs_dir):
        if f.endswith(('.xlsx', '.xls', '.et')) and ('budget' in f.lower() or 'variance' in f.lower()):
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

        starter = {"Budget", "Actuals"}
        new_sheets = [s for s in wb.sheetnames if s not in starter]
        result["new_sheet_count"] = len(new_sheets)

        result["has_variance_sheet"] = any('variance' in s.lower() and 'monthly' in s.lower() for s in wb.sheetnames) or \
                                       any('month' in s.lower() and 'var' in s.lower() for s in wb.sheetnames) or \
                                       any(s.lower() in ['monthly_variance', 'variance', 'monthly_var'] for s in wb.sheetnames)
        result["has_ytd_sheet"] = any('ytd' in s.lower() or 'year' in s.lower() for s in wb.sheetnames)
        result["has_executive_sheet"] = any('exec' in s.lower() or 'summary' in s.lower() or 'dashboard' in s.lower() for s in wb.sheetnames)

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

        chart_count = 0
        for sn in wb.sheetnames:
            sheet = wb[sn]
            if hasattr(sheet, '_charts'):
                chart_count += len(sheet._charts)
        result["has_chart"] = chart_count > 0
        result["chart_count"] = chart_count

    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "No budget workbook found"

result["task_start"] = task_start

with open("/tmp/budget_variance_result.json", "w") as f:
    json.dump(result, f)
print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/budget_variance_result.json 2>/dev/null || true
echo "=== Export complete ==="
