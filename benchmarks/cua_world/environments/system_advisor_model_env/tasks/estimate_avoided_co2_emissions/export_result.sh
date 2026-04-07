#!/bin/bash
echo "=== Exporting CO2 Emissions Task Results ==="

RESULT_FILE="/home/ga/Documents/SAM_Projects/co2_avoided_report.json"
EXPORT_FILE="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Initialize export file
cat > "$EXPORT_FILE" << EOF
{
    "file_exists": false,
    "file_created_during_task": false,
    "file_size_bytes": 0,
    "valid_json": false,
    "has_all_fields": false,
    "parsed_values": {},
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Process results safely via Python
if [ -f "$RESULT_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$RESULT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$RESULT_FILE" 2>/dev/null || echo "0")
    
    python3 << PYEOF
import json
import sys

export_file = "$EXPORT_FILE"
result_file = "$RESULT_FILE"
task_start = int("$TASK_START")
file_size = int("$FILE_SIZE")
file_mtime = int("$FILE_MTIME")

# Load base export data
with open(export_file, 'r') as f:
    result = json.load(f)

result["file_exists"] = True
result["file_created_during_task"] = file_mtime > task_start
result["file_size_bytes"] = file_size
result["file_mtime"] = file_mtime

required_fields = [
    "system_capacity_kw",
    "tilt_deg",
    "azimuth_deg",
    "annual_energy_kwh",
    "annual_energy_mwh",
    "emission_factor_mt_co2_per_mwh",
    "avoided_co2_mt",
    "equivalent_cars_removed",
    "equivalent_trees_planted",
    "weather_file_used"
]

try:
    with open(result_file, 'r') as f:
        data = json.load(f)
    result["valid_json"] = True
    
    missing = [field for field in required_fields if field not in data]
    result["has_all_fields"] = len(missing) == 0
    result["missing_fields"] = missing
    result["parsed_values"] = {}
    
    for field in required_fields:
        if field in data:
            result["parsed_values"][field] = data[field]
            
except json.JSONDecodeError as e:
    result["json_error"] = str(e)
except Exception as e:
    result["error"] = str(e)

with open(export_file, 'w') as f:
    json.dump(result, f, indent=2)
PYEOF
fi

chmod 666 "$EXPORT_FILE" 2>/dev/null || true

echo "Export completed. Results:"
cat "$EXPORT_FILE"
echo "=== Export complete ==="