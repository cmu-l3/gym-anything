#!/bin/bash
echo "=== Exporting project finance results ==="

RESULT_FILE="/home/ga/Documents/SAM_Projects/daggett_100mw_finance.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_JSON="/tmp/task_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Check if script ran Python
PYTHON_RAN="false"
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Use Python to evaluate the JSON file robustly
python3 << PYEOF
import json
import sys
import os

result_file = "$RESULT_FILE"
task_start = int("$TASK_START")
output_json_path = "$OUTPUT_JSON"

data = {}
file_exists = False
modified_during_task = False
file_size = 0
error_msg = None

if os.path.exists(result_file):
    file_exists = True
    file_size = os.path.getsize(result_file)
    mtime = int(os.path.getmtime(result_file))
    
    if mtime > task_start:
        modified_during_task = True
        
    try:
        with open(result_file, 'r') as f:
            data = json.load(f)
    except Exception as e:
        error_msg = f"Invalid JSON format: {str(e)}"
else:
    error_msg = "File does not exist"

required_fields = [
    "year1_energy_kwh", "capacity_factor_percent",
    "lcoe_real_cents_per_kwh", "lcoe_nom_cents_per_kwh",
    "project_irr_aftertax_percent", "equity_irr_aftertax_percent",
    "npv_aftertax_dollars", "min_dscr",
    "ppa_price_year1_cents_per_kwh", "debt_fraction_percent",
    "total_installed_cost_dollars",
    "cashflow_aftertax", "annual_energy_kwh"
]

fields_present = {}
if isinstance(data, dict):
    for f in required_fields:
        fields_present[f] = (f in data)
else:
    for f in required_fields:
        fields_present[f] = False

all_fields_present = all(fields_present.values())

output = {
    "file_exists": file_exists,
    "file_size": file_size,
    "modified_during_task": modified_during_task,
    "python_ran": "$PYTHON_RAN" == "true",
    "all_fields_present": all_fields_present,
    "fields_present": fields_present,
    "error": error_msg,
    "data": data if isinstance(data, dict) else {}
}

try:
    with open(output_json_path, "w") as f:
        json.dump(output, f, indent=2)
except Exception as e:
    print(f"Error writing export file: {e}")
PYEOF

chmod 666 "$OUTPUT_JSON" 2>/dev/null || true

echo "Export logic completed."
cat "$OUTPUT_JSON"
echo "=== Export complete ==="