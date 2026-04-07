#!/bin/bash
echo "=== Exporting task result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DATA_FILE="/home/ga/Documents/menu_sales_data.xlsx"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract evaluated spreadsheet state using openpyxl in data_only mode
# This gets the calculated values of the formulas the agent wrote
python3 << PYEOF
import json
import os
import sys

result = {
    "file_exists": False,
    "file_mtime": 0,
    "task_start": $TASK_START,
    "sheets": [],
    "pos_data": [],
    "summary_data": [],
    "j2_value": None,
    "k2_value": None,
    "error": None
}

file_path = "$DATA_FILE"

if os.path.exists(file_path):
    result["file_exists"] = True
    result["file_mtime"] = int(os.path.getmtime(file_path))
    
    try:
        from openpyxl import load_workbook
        # Load with data_only=True to get formula results
        wb = load_workbook(file_path, data_only=True)
        result["sheets"] = wb.sheetnames
        
        if "POS_Export" in wb.sheetnames:
            ws = wb["POS_Export"]
            # Extract J2 and K2
            result["j2_value"] = ws['J2'].value
            result["k2_value"] = ws['K2'].value
            
            # Extract rows
            for row in ws.iter_rows(min_row=2, max_row=21, values_only=True):
                if row[0]: # If Item Name exists
                    # Append (Qty, Cost, Price, Unit_CM, Total_Rev, Total_CM, Classification)
                    result["pos_data"].append({
                        "qty": row[2],
                        "cost": row[3],
                        "price": row[4],
                        "unit_cm": row[5],
                        "total_rev": row[6],
                        "total_cm": row[7],
                        "classification": row[8]
                    })
                    
        # Find summary sheet (case insensitive check in verifier, just grab data if exists)
        summary_sheet_name = next((s for s in wb.sheetnames if 'summary' in s.lower()), None)
        if summary_sheet_name:
            ws_sum = wb[summary_sheet_name]
            for row in ws_sum.iter_rows(min_row=1, max_row=10, values_only=True):
                if row[0] is not None:
                    result["summary_data"].append({"category": str(row[0]), "count": row[1]})
                    
    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result extracted to /tmp/task_result.json"
echo "=== Export complete ==="