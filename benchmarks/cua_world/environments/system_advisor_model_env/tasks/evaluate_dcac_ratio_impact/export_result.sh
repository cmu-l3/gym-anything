#!/bin/bash
echo "=== Exporting DC/AC Ratio Comparison Results ==="

RESULT_FILE="/home/ga/Documents/SAM_Projects/dcac_ratio_comparison.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_JSON="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check python execution
PYTHON_RAN="false"
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check PySAM imports
PY_FILES=$(find /home/ga -name "*.py" -newer /tmp/task_start_time.txt 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    for pyf in $PY_FILES; do
        if grep -ql "import PySAM\|from PySAM\|import Pvwatts\|Pvwattsv" "$pyf" 2>/dev/null; then
            PYTHON_RAN="true"
            break
        fi
    done
fi

FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$RESULT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$RESULT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Use Python to safely parse the user's output JSON and flatten it for the verifier
python3 << PYEOF > "$OUTPUT_JSON"
import json
import os

result_file = "$RESULT_FILE"
output = {
    "file_exists": "$FILE_EXISTS" == "true",
    "file_modified": "$FILE_MODIFIED" == "true",
    "file_size": int("$FILE_SIZE"),
    "python_ran": "$PYTHON_RAN" == "true",
    "valid_json": False,
    "has_config_a": False,
    "has_config_b": False,
    "energy_gain_percent": None,
    "weather_file_used": None,
    "a_ratio": None,
    "a_energy": None,
    "a_cf": None,
    "b_ratio": None,
    "b_energy": None,
    "b_cf": None
}

if output["file_exists"]:
    try:
        with open(result_file, 'r') as f:
            data = json.load(f)
        output["valid_json"] = True
        output["weather_file_used"] = data.get("weather_file_used")
        output["energy_gain_percent"] = data.get("energy_gain_percent")
        
        if "config_a" in data:
            output["has_config_a"] = True
            output["a_ratio"] = data["config_a"].get("dc_ac_ratio")
            output["a_energy"] = data["config_a"].get("annual_energy_kwh")
            output["a_cf"] = data["config_a"].get("capacity_factor_percent")
            
        if "config_b" in data:
            output["has_config_b"] = True
            output["b_ratio"] = data["config_b"].get("dc_ac_ratio")
            output["b_energy"] = data["config_b"].get("annual_energy_kwh")
            output["b_cf"] = data["config_b"].get("capacity_factor_percent")
    except Exception as e:
        output["parse_error"] = str(e)

print(json.dumps(output, indent=2))
PYEOF

chmod 666 "$OUTPUT_JSON" 2>/dev/null || true
echo "Result JSON saved to $OUTPUT_JSON"
cat "$OUTPUT_JSON"

echo "=== Export complete ==="