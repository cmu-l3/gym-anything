#!/bin/bash
echo "=== Exporting Solar Water Heating task results ==="

RESULT_FILE="/home/ga/Documents/SAM_Projects/swh_results.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if result file exists and get modification metadata
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$RESULT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$RESULT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Parse the JSON result file robustly using Python
python3 << 'PYEOF' > /tmp/swh_parsed.json 2>/dev/null
import json
import sys

result = {
    "valid_json": False,
    "annual_energy": None,
    "solar_fraction": None,
    "monthly_count": 0,
    "summer_energy": None,
    "winter_energy": None,
    "has_system_params": False,
    "ncoll": None,
    "area_coll": None,
    "tilt": None,
    "azimuth": None,
    "V_tank": None
}

try:
    with open("/home/ga/Documents/SAM_Projects/swh_results.json", "r") as f:
        data = json.load(f)
    
    result["valid_json"] = True
    
    # Try different common parameter names the agent might use
    result["annual_energy"] = data.get("annual_energy_kwh", data.get("annual_energy", None))
    result["solar_fraction"] = data.get("solar_fraction", None)
    
    monthly = data.get("monthly_energy_kwh", data.get("monthly_energy", []))
    if isinstance(monthly, list):
        result["monthly_count"] = len(monthly)
        # Summer (Jun=index 5, Jul=index 6, Aug=index 7) vs Winter (Dec=index 11, Jan=index 0, Feb=index 1)
        if len(monthly) == 12:
            try:
                summer = sum([float(monthly[5]), float(monthly[6]), float(monthly[7])])
                winter = sum([float(monthly[11]), float(monthly[0]), float(monthly[1])])
                result["summer_energy"] = summer
                result["winter_energy"] = winter
            except (ValueError, TypeError):
                pass

    params = data.get("system_parameters", {})
    if isinstance(params, dict) and len(params) > 0:
        result["has_system_params"] = True
        result["ncoll"] = params.get("ncoll")
        result["area_coll"] = params.get("area_coll")
        result["tilt"] = params.get("tilt")
        result["azimuth"] = params.get("azimuth")
        result["V_tank"] = params.get("V_tank")
        
except Exception as e:
    result["error"] = str(e)

with open("/tmp/swh_parsed_clean.json", "w") as f:
    json.dump(result, f)
PYEOF

# Combine with bash-level checks
if [ -f /tmp/swh_parsed_clean.json ]; then
    PARSED_DATA=$(cat /tmp/swh_parsed_clean.json)
else
    PARSED_DATA='{"valid_json": false}'
fi

# Check for Python script files as evidence of work
SCRIPT_FILES=$(find /home/ga -name "*.py" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)

# Build final output JSON using jq for safety
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_created_during_task "$FILE_CREATED_DURING_TASK" \
    --argjson script_files_created "$SCRIPT_FILES" \
    --argjson parsed_data "$PARSED_DATA" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_created_during_task: $file_created_during_task,
        script_files_created: $script_files_created,
        parsed_data: $parsed_data
    }' > "$OUTPUT"

chmod 666 "$OUTPUT" 2>/dev/null || true

echo "Task result exported to $OUTPUT"
cat "$OUTPUT"