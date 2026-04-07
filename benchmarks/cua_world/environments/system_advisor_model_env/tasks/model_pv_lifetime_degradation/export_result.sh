#!/bin/bash
echo "=== Exporting lifetime degradation results ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

RESULT_FILE="/home/ga/Documents/SAM_Projects/lifetime_degradation_results.json"
EXPORT_FILE="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if file exists
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
MODIFIED_DURING_TASK="false"

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$RESULT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$RESULT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    fi
fi

# Parse JSON safely using Python
python3 << PYEOF
import json
import sys

export_data = {
    "file_exists": ${FILE_EXISTS},
    "file_modified_during_task": ${MODIFIED_DURING_TASK},
    "file_size_bytes": ${FILE_SIZE},
    "parse_success": False,
    "keys_present": [],
    "keys_missing": [],
    "values": {}
}

required_keys = [
    "weather_file_used", "location_description", "system_capacity_kw",
    "dc_ac_ratio", "tilt_degrees", "azimuth_degrees",
    "degradation_rate_pct_per_year", "analysis_period_years",
    "year1_annual_energy_kwh", "year25_annual_energy_kwh",
    "cumulative_25yr_energy_kwh", "lifetime_capacity_factor",
    "total_degradation_loss_kwh", "annual_energy_by_year_kwh"
]

if export_data["file_exists"]:
    try:
        with open("${RESULT_FILE}", "r") as f:
            data = json.load(f)
            
        present = [k for k in required_keys if k in data]
        missing = [k for k in required_keys if k not in data]
        
        values = {}
        for k in required_keys:
            if k in data:
                values[k] = data[k]
                
        export_data["parse_success"] = True
        export_data["keys_present"] = present
        export_data["keys_missing"] = missing
        export_data["values"] = values
    except Exception as e:
        export_data["error"] = str(e)
        export_data["keys_missing"] = required_keys

with open("${EXPORT_FILE}", "w") as f:
    json.dump(export_data, f, indent=2)
PYEOF

chmod 666 "$EXPORT_FILE" 2>/dev/null || true

echo "Export complete. Payload:"
cat "$EXPORT_FILE"
echo "=== Export complete ==="