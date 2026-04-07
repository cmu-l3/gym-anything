#!/bin/bash
echo "=== Exporting palmer_penguins_analysis_pippy task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/palmer_penguins_task_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/palmer_penguins_start_ts 2>/dev/null || echo "0")
SCRIPT_PATH="/home/ga/Documents/penguin_analysis.py"
REPORT_PATH="/home/ga/Documents/penguin_summary.txt"

SCRIPT_MODIFIED="false"
REPORT_MODIFIED="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_MTIME=$(stat --format=%Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

if [ -f "$REPORT_PATH" ]; then
    REPORT_MTIME=$(stat --format=%Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_MODIFIED="true"
    fi
fi

# Run python script to analyze the contents of the generated files
python3 << 'PYEOF' > /tmp/penguin_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/penguin_analysis.json
import json
import os
import re

result = {
    "script_exists": False,
    "script_reads_file": False,
    "script_size": 0,
    "report_exists": False,
    "report_size": 0,
    "adelie_numbers": [],
    "chinstrap_numbers": [],
    "gentoo_numbers": [],
    "has_5076_0": False
}

script_path = "/home/ga/Documents/penguin_analysis.py"
report_path = "/home/ga/Documents/penguin_summary.txt"

if os.path.exists(script_path):
    result["script_exists"] = True
    result["script_size"] = os.path.getsize(script_path)
    try:
        with open(script_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            # Check for basic evidence of parsing
            if 'open(' in content or 'csv' in content or 'pandas' in content:
                result["script_reads_file"] = True
    except:
        pass

if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_size"] = os.path.getsize(report_path)
    try:
        with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
            # Specifically check for exact Gentoo mass to enforce formatting rule
            if '5076.0' in content:
                result["has_5076_0"] = True
                
            lines = content.split('\n')
            for line in lines:
                line_lower = line.lower()
                # Find all decimal-formatted numbers
                nums = re.findall(r'\d+\.\d+', line)
                if 'adelie' in line_lower:
                    result["adelie_numbers"].extend(nums)
                elif 'chinstrap' in line_lower:
                    result["chinstrap_numbers"].extend(nums)
                elif 'gentoo' in line_lower:
                    result["gentoo_numbers"].extend(nums)
    except:
        pass

print(json.dumps(result))
PYEOF

# Merge bash modification variables into the JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 << PYEOF > "$TEMP_JSON"
import json
try:
    with open('/tmp/penguin_analysis.json', 'r') as f:
        data = json.load(f)
except:
    data = {}

data["script_modified"] = "$SCRIPT_MODIFIED" == "true"
data["report_modified"] = "$REPORT_MODIFIED" == "true"

with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f)
PYEOF

# Move to final accessible location
rm -f /tmp/palmer_penguins_result.json 2>/dev/null || sudo rm -f /tmp/palmer_penguins_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/palmer_penguins_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/palmer_penguins_result.json
chmod 666 /tmp/palmer_penguins_result.json 2>/dev/null || sudo chmod 666 /tmp/palmer_penguins_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/palmer_penguins_result.json"
cat /tmp/palmer_penguins_result.json
echo "=== Export complete ==="