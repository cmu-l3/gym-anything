#!/bin/bash
set -euo pipefail

echo "=== Exporting Fixed Asset Depreciation Result ==="

# Capture final screen state before doing anything
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if ONLYOFFICE is running and attempt a graceful save (Ctrl+S) and exit (Ctrl+Q)
if pgrep -f "onlyoffice-desktopeditors|DesktopEditors" > /dev/null; then
    echo "Attempting to save and close ONLYOFFICE..."
    WID=$(DISPLAY=:1 wmctrl -l | grep -i 'ONLYOFFICE\|Desktop Editors' | awk '{print $1; exit}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        sleep 1
        su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" 2>/dev/null || true
        sleep 2
        su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+q" 2>/dev/null || true
        sleep 2
    fi
fi

# Kill remaining instances if any
pkill -f "onlyoffice-desktopeditors|DesktopEditors" 2>/dev/null || true
sleep 1

# Gather information about the file output
OUTPUT_PATH="/home/ga/Documents/Spreadsheets/depreciation_schedule_2023.xlsx"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")
fi

START_TS=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
CREATED_DURING_TASK="false"
if [ "$FILE_MTIME" -gt "$START_TS" ]; then
    CREATED_DURING_TASK="true"
fi

# Python script to extract data safely inside the container (to avoid host dependency issues)
cat > /tmp/extract_spreadsheet_data.py << 'PYEOF'
import json
import sys
import os

result = {
    "success": False,
    "error": "",
    "sheets": [],
    "all_text": "",
    "all_numbers": [],
    "formula_count": 0
}

file_path = "/home/ga/Documents/Spreadsheets/depreciation_schedule_2023.xlsx"

if os.path.exists(file_path):
    try:
        from openpyxl import load_workbook
        
        all_text = []
        all_numbers = []
        
        # Load with data_only=True to get calculated values
        wb_data = load_workbook(file_path, data_only=True)
        result["sheets"] = wb_data.sheetnames
        
        for sn in wb_data.sheetnames:
            sheet = wb_data[sn]
            for row in sheet.iter_rows(max_row=500, max_col=50):
                for cell in row:
                    if cell.value is not None:
                        all_text.append(str(cell.value).lower())
                        if isinstance(cell.value, (int, float)):
                            all_numbers.append(cell.value)
                            
        # Convert numeric values to Python floats
        result["all_numbers"] = [float(x) for x in all_numbers]
        result["all_text"] = " ".join(all_text)
        
        wb_data.close()

        # Load with data_only=False to count formulas
        wb_formulas = load_workbook(file_path, data_only=False)
        formula_count = 0
        for sn in wb_formulas.sheetnames:
            sheet = wb_formulas[sn]
            for row in sheet.iter_rows(max_row=500, max_col=50):
                for cell in row:
                    if isinstance(cell.value, str) and str(cell.value).startswith('='):
                        formula_count += 1
                        
        result["formula_count"] = formula_count
        result["success"] = True
        wb_formulas.close()
        
    except Exception as e:
        result["error"] = str(e)

# Write final output to be read by verifier
with open('/tmp/depreciation_task_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

python3 /tmp/extract_spreadsheet_data.py

# Inject file existence/timing data into the json
TEMP_JSON=$(mktemp)
jq ". + {
    \"file_exists\": $FILE_EXISTS,
    \"file_size\": $FILE_SIZE,
    \"created_during_task\": $CREATED_DURING_TASK
}" /tmp/depreciation_task_result.json > "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/depreciation_task_result.json
chmod 666 /tmp/depreciation_task_result.json

echo "=== Export Complete ==="