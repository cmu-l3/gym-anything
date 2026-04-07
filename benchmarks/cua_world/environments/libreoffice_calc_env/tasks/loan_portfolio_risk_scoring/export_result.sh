#!/bin/bash
source /workspace/scripts/task_utils.sh

take_screenshot "/tmp/loan_risk_final.png" || true

# Save the file in LibreOffice Calc
WID=$(get_calc_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    focus_window "$WID" || true
    sleep 1
    # Save as the new file
    safe_xdotool ga :1 key --delay 300 ctrl+shift+s 2>/dev/null || true
    sleep 2
    # Try to type the output filename
    safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/loan_portfolio_complete.xlsx' 2>/dev/null || true
    sleep 1
    safe_xdotool ga :1 key --delay 300 Return 2>/dev/null || true
    sleep 2
    safe_xdotool ga :1 key --delay 300 Return 2>/dev/null || true
    sleep 3
    # Also try plain save
    safe_xdotool ga :1 key --delay 300 ctrl+s 2>/dev/null || true
    sleep 2
    safe_xdotool ga :1 key --delay 300 Return 2>/dev/null || true
    sleep 2
fi

# Check for output files
OUTPUT_FILE=""
if [ -f "/home/ga/Documents/loan_portfolio_complete.xlsx" ]; then
    OUTPUT_FILE="/home/ga/Documents/loan_portfolio_complete.xlsx"
elif [ -f "/home/ga/Documents/loan_portfolio_complete.ods" ]; then
    OUTPUT_FILE="/home/ga/Documents/loan_portfolio_complete.ods"
elif [ -f "/home/ga/Documents/loan_portfolio_partial.xlsx" ]; then
    OUTPUT_FILE="/home/ga/Documents/loan_portfolio_partial.xlsx"
fi

echo "Output file: ${OUTPUT_FILE:-NONE}"

# Write result JSON entirely from Python to avoid shell variable expansion issues
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")

python3 << PYEOF
import json, os, sys

task_start_str = "${TASK_START}"
try:
    task_start = int(task_start_str)
except ValueError:
    task_start = 0

output_file = "${OUTPUT_FILE:-}"
output_file_exists = bool(output_file and os.path.exists(output_file))

parsed_data = {}
if output_file and os.path.exists(output_file):
    try:
        import openpyxl
        wb = openpyxl.load_workbook(output_file, data_only=True)
        result = {'sheets': {}, 'file_path': output_file}
        for sheet_name in wb.sheetnames:
            ws = wb[sheet_name]
            sheet_data = []
            for row in ws.iter_rows(values_only=True):
                row_data = []
                for val in row:
                    if val is not None and not isinstance(val, (int, float, bool, str)):
                        val = str(val)
                    row_data.append(val)
                sheet_data.append(row_data)
            result['sheets'][sheet_name] = sheet_data
        parsed_data = result
    except Exception as e:
        parsed_data = {'error': str(e), 'file_path': output_file}

final = {
    'task_start': task_start,
    'output_file': output_file,
    'output_file_exists': output_file_exists,
    'parsed_data': parsed_data,
}

with open('/tmp/loan_risk_result.json', 'w') as f:
    json.dump(final, f, default=str)

print('Export JSON written to /tmp/loan_risk_result.json')
PYEOF

chmod 666 /tmp/loan_risk_result.json
echo "Export complete."
