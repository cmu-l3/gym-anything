#!/bin/bash
echo "=== Exporting financial_consolidation_analysis result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/financial_consolidation_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/financial_consolidation_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/financial_consolidation_start_ts 2>/dev/null || echo "0")

python3 << 'PYEOF'
import json
import os

result = {
    "file_exists": False,
    "file_is_new": False,
    "sheets": [],
    "has_consolidated_sheet": False,
    "has_ratios_sheet": False,
    "has_variance_sheet": False,
    "has_dashboard_sheet": False,
    "new_sheet_count": 0,
    "formula_count": 0,
    "has_conditional_formatting": False,
    "has_chart": False,
    "error": None
}

task_start = int(open('/tmp/financial_consolidation_start_ts').read().strip()) if os.path.exists('/tmp/financial_consolidation_start_ts') else 0

target_file = "/home/ga/Documents/meridian_holdings_consolidation.xlsx"

# Also check if agent saved to a different name
candidates = [target_file]
docs_dir = "/home/ga/Documents/"
if os.path.isdir(docs_dir):
    for f in os.listdir(docs_dir):
        if f.endswith(('.xlsx', '.xls', '.et')) and 'consolidat' in f.lower():
            candidates.append(os.path.join(docs_dir, f))
        if f.endswith(('.xlsx', '.xls', '.et')) and 'meridian' in f.lower():
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

        starter_sheets = {"Alpha_Inc", "Beta_Corp", "Gamma_LLC", "Intercompany", "Prior_Year"}
        new_sheets = [s for s in wb.sheetnames if s not in starter_sheets]
        result["new_sheet_count"] = len(new_sheets)

        # Check for expected new sheets
        sheet_lower = {s.lower(): s for s in wb.sheetnames}
        result["has_consolidated_sheet"] = any('consolidat' in s.lower() for s in wb.sheetnames)
        result["has_ratios_sheet"] = any('ratio' in s.lower() for s in wb.sheetnames)
        result["has_variance_sheet"] = any('variance' in s.lower() or 'var_' in s.lower() for s in wb.sheetnames)
        result["has_dashboard_sheet"] = any('dashboard' in s.lower() or 'chart' in s.lower() for s in wb.sheetnames)

        # Count formulas in new sheets
        formula_count = 0
        for sn in new_sheets:
            sheet = wb[sn]
            for row in sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                        formula_count += 1
        result["formula_count"] = formula_count

        # Check conditional formatting in any sheet
        for sn in wb.sheetnames:
            sheet = wb[sn]
            if sheet.conditional_formatting:
                for rule in sheet.conditional_formatting:
                    result["has_conditional_formatting"] = True
                    break
            if result["has_conditional_formatting"]:
                break

        # Check for charts
        for sn in wb.sheetnames:
            sheet = wb[sn]
            if hasattr(sheet, '_charts') and len(sheet._charts) > 0:
                result["has_chart"] = True
                break

    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "No consolidation workbook found"

result["task_start"] = task_start

with open("/tmp/financial_consolidation_result.json", "w") as f:
    json.dump(result, f)

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/financial_consolidation_result.json 2>/dev/null || true
echo "=== Export complete ==="
