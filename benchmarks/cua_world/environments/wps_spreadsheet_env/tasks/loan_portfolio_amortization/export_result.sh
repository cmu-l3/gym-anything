#!/bin/bash
echo "=== Exporting loan_portfolio_amortization result ==="

DISPLAY=:1 import -window root /tmp/loan_portfolio_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/loan_portfolio_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/loan_portfolio_start_ts 2>/dev/null || echo "0")

python3 << 'PYEOF'
import json
import os

result = {
    "file_exists": False,
    "file_is_new": False,
    "sheets": [],
    "amortization_sheet_count": 0,
    "has_portfolio_summary": False,
    "has_covenant_sheet": False,
    "has_sensitivity_sheet": False,
    "new_sheet_count": 0,
    "formula_count": 0,
    "has_financial_formulas": False,
    "has_conditional_formatting": False,
    "error": None
}

task_start = int(open('/tmp/loan_portfolio_start_ts').read().strip()) if os.path.exists('/tmp/loan_portfolio_start_ts') else 0

candidates = ["/home/ga/Documents/loan_portfolio_model.xlsx"]
docs_dir = "/home/ga/Documents/"
if os.path.isdir(docs_dir):
    for f in os.listdir(docs_dir):
        if f.endswith(('.xlsx', '.xls', '.et')) and ('loan' in f.lower() or 'portfolio' in f.lower() or 'amort' in f.lower()):
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

        starter = {"Loan_Terms", "Rate_Curve", "Property_NOI"}
        new_sheets = [s for s in wb.sheetnames if s not in starter]
        result["new_sheet_count"] = len(new_sheets)

        # Count amortization sheets (named LOAN-xxx)
        amort_sheets = [s for s in wb.sheetnames if s.startswith('LOAN-') or 'amort' in s.lower()]
        result["amortization_sheet_count"] = len(amort_sheets)

        result["has_portfolio_summary"] = any('portfolio' in s.lower() or 'summary' in s.lower() for s in wb.sheetnames)
        result["has_covenant_sheet"] = any('covenant' in s.lower() or 'dscr' in s.lower() or 'compliance' in s.lower() for s in wb.sheetnames)
        result["has_sensitivity_sheet"] = any('sensitiv' in s.lower() or 'scenario' in s.lower() or 'what-if' in s.lower() for s in wb.sheetnames)

        formula_count = 0
        has_pmt = False
        has_ipmt = False
        has_ppmt = False
        for sn in new_sheets:
            sheet = wb[sn]
            for row in sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                        formula_count += 1
                        fu = cell.value.upper()
                        if 'PMT' in fu and 'IPMT' not in fu and 'PPMT' not in fu:
                            has_pmt = True
                        if 'IPMT' in fu:
                            has_ipmt = True
                        if 'PPMT' in fu:
                            has_ppmt = True

        result["formula_count"] = formula_count
        result["has_financial_formulas"] = has_pmt or has_ipmt or has_ppmt
        result["has_pmt"] = has_pmt
        result["has_ipmt"] = has_ipmt
        result["has_ppmt"] = has_ppmt

        for sn in wb.sheetnames:
            sheet = wb[sn]
            if sheet.conditional_formatting:
                result["has_conditional_formatting"] = True
                break

    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "No loan portfolio workbook found"

result["task_start"] = task_start

with open("/tmp/loan_portfolio_result.json", "w") as f:
    json.dump(result, f)
print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/loan_portfolio_result.json 2>/dev/null || true
echo "=== Export complete ==="
