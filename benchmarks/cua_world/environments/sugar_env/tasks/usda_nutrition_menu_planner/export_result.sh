#!/bin/bash
echo "=== Exporting usda_nutrition_menu_planner task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
SCRIPT_PATH="/home/ga/Documents/nutrition_analyzer.py"
REPORT_PATH="/home/ga/Documents/nutrition_report.txt"

# Verify File Creation and Timestamps
SCRIPT_EXISTS="false"
REPORT_EXISTS="false"
FILES_CREATED_DURING_TASK="false"
SCRIPT_USES_IO="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -ge "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
    # Quick anti-gaming check: does the script contain file IO keywords?
    if grep -qE "(open|csv|read|pandas|with )" "$SCRIPT_PATH"; then
        SCRIPT_USES_IO="true"
    fi
fi

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
    
    # Use a Python snippet to parse the text report cleanly
    python3 << 'PYEOF' > /tmp/report_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/report_analysis.json
import json
import re

result = {
    "has_iron_header": False,
    "has_vitc_header": False,
    "has_protein_header": False,
    "has_stats_header": False,
    "iron_section": "",
    "vitc_section": "",
    "protein_section": "",
    "stats_section": ""
}

current_section = None

try:
    with open('/home/ga/Documents/nutrition_report.txt', 'r') as f:
        for line in f:
            line_upper = line.upper()
            
            # Check for headers
            if "HIGH IRON" in line_upper:
                current_section = "iron_section"
                result["has_iron_header"] = True
            elif "VITAMIN C" in line_upper:
                current_section = "vitc_section"
                result["has_vitc_header"] = True
            elif "HIGH PROTEIN" in line_upper:
                current_section = "protein_section"
                result["has_protein_header"] = True
            elif "STATISTICS" in line_upper:
                current_section = "stats_section"
                result["has_stats_header"] = True
            elif current_section:
                # Append line to current section
                result[current_section] += line.strip() + " "

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

else:
    echo '{"error":"file_not_found"}' > /tmp/report_analysis.json
fi

# Merge bash variables with the Python JSON object
TEMP_JSON=$(mktemp)
python3 << PYEOF > "$TEMP_JSON"
import json
import os

try:
    with open('/tmp/report_analysis.json', 'r') as f:
        data = json.load(f)
except:
    data = {}

data["script_exists"] = "$SCRIPT_EXISTS" == "true"
data["report_exists"] = "$REPORT_EXISTS" == "true"
data["files_created_during_task"] = "$FILES_CREATED_DURING_TASK" == "true"
data["script_uses_io"] = "$SCRIPT_USES_IO" == "true"

with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f)
PYEOF

rm -f /tmp/usda_nutrition_result.json 2>/dev/null || sudo rm -f /tmp/usda_nutrition_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/usda_nutrition_result.json
chmod 666 /tmp/usda_nutrition_result.json
rm -f "$TEMP_JSON" /tmp/report_analysis.json

echo "Export Complete. Result:"
cat /tmp/usda_nutrition_result.json
echo "=== Export complete ==="