#!/bin/bash
echo "=== Exporting geothermal task results ==="

RESULT_FILE="/home/ga/Documents/SAM_Projects/geothermal_results.json"
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/geothermal_model.py"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Initialize export object
echo '{}' > "$EXPORT"

# Check results file
if [ -f "$RESULT_FILE" ]; then
    FILE_MOD=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c %s "$RESULT_FILE" 2>/dev/null || echo "0")
    
    # Check if created/modified during task
    if [ "$FILE_MOD" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Parse JSON fields with Python to ensure format safety
    python3 << PYEOF
import json
import sys

try:
    with open("$RESULT_FILE", 'r') as f:
        d = json.load(f)
        
    def get_val(key, default="MISSING"):
        val = d.get(key)
        return str(val) if val is not None else default

    out = {
        "results_exist": True,
        "valid_json": True,
        "file_mod_time": int("$FILE_MOD"),
        "file_size": int("$FILE_SIZE"),
        "task_start_time": int("$TASK_START"),
        "file_created_during_task": "$FILE_CREATED_DURING_TASK" == "true",
        "resource_temp_c": get_val('resource_temp_c'),
        "conversion_type": get_val('conversion_type'),
        "nameplate_kw": get_val('nameplate_kw'),
        "annual_energy_kwh": get_val('annual_energy_kwh'),
        "capacity_factor": get_val('capacity_factor'),
        "lcoe_cents_per_kwh": get_val('lcoe_cents_per_kwh'),
        "num_wells": get_val('num_wells'),
        "weather_file": get_val('weather_file')
    }
    with open("$EXPORT", "w") as f:
        json.dump(out, f, indent=2)
except Exception as e:
    out = {
        "results_exist": True,
        "valid_json": False,
        "file_mod_time": int("$FILE_MOD"),
        "file_size": int("$FILE_SIZE"),
        "task_start_time": int("$TASK_START"),
        "file_created_during_task": "$FILE_CREATED_DURING_TASK" == "true",
        "error": str(e)
    }
    with open("$EXPORT", "w") as f:
        json.dump(out, f, indent=2)
PYEOF
else
    # Results file doesn't exist
    python3 << PYEOF
import json
out = {
    "results_exist": False,
    "valid_json": False,
    "file_mod_time": 0,
    "file_size": 0,
    "task_start_time": int("$TASK_START"),
    "file_created_during_task": False
}
with open("$EXPORT", "w") as f:
    json.dump(out, f, indent=2)
PYEOF
fi

# Append script file info
SCRIPT_EXISTS="false"
SCRIPT_HAS_PYSAM="false"
SCRIPT_HAS_GEOTHERMAL="false"

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    grep -q "PySAM" "$SCRIPT_FILE" 2>/dev/null && SCRIPT_HAS_PYSAM="true"
    grep -q "Geothermal" "$SCRIPT_FILE" 2>/dev/null && SCRIPT_HAS_GEOTHERMAL="true"
fi

python3 << PYEOF
import json
with open("$EXPORT", "r") as f:
    data = json.load(f)

data["script_exists"] = "$SCRIPT_EXISTS" == "true"
data["script_has_pysam"] = "$SCRIPT_HAS_PYSAM" == "true"
data["script_has_geothermal"] = "$SCRIPT_HAS_GEOTHERMAL" == "true"

with open("$EXPORT", "w") as f:
    json.dump(data, f, indent=2)
PYEOF

chmod 666 "$EXPORT"
echo "Exported data:"
cat "$EXPORT"
echo "=== Export complete ==="