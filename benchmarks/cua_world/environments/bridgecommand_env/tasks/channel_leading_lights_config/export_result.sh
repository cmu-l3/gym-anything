#!/bin/bash
echo "=== Exporting channel_leading_lights_config results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SCENARIO_DIR="/opt/bridgecommand/Scenarios/l) Leading Lights Setup"
OTHERSHIP_FILE="$SCENARIO_DIR/othership.ini"
OWNSHIP_FILE="$SCENARIO_DIR/ownship.ini"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if scenario files exist
SCENARIO_EXISTS="false"
FILES_CREATED_DURING_TASK="false"
OTHERSHIP_EXISTS="false"

if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
    
    if [ -f "$OTHERSHIP_FILE" ]; then
        OTHERSHIP_EXISTS="true"
        FILE_MTIME=$(stat -c %Y "$OTHERSHIP_FILE" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            FILES_CREATED_DURING_TASK="true"
        fi
    fi
fi

# Python script to parse the INI files and extract coordinates
# Bridge Command INI files are not standard (Key(N)=Value), so we use custom parsing
python3 << PYEOF
import json
import os
import re

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "scenario_exists": False,
    "othership_exists": False,
    "ownship_exists": False,
    "objects": [],
    "ownship": {}
}

scenario_dir = "$SCENARIO_DIR"
othership_path = "$OTHERSHIP_FILE"
ownship_path = "$OWNSHIP_FILE"

if os.path.isdir(scenario_dir):
    result["scenario_exists"] = True

# Parse Ownship
if os.path.exists(ownship_path):
    result["ownship_exists"] = True
    try:
        with open(ownship_path, 'r') as f:
            content = f.read()
            lat_match = re.search(r'InitialLat\s*=\s*([0-9.-]+)', content, re.IGNORECASE)
            long_match = re.search(r'InitialLong\s*=\s*([0-9.-]+)', content, re.IGNORECASE)
            
            if lat_match: result["ownship"]["lat"] = float(lat_match.group(1))
            if long_match: result["ownship"]["long"] = float(long_match.group(1))
    except Exception as e:
        result["ownship_error"] = str(e)

# Parse Othership (Traffic/Lights)
if os.path.exists(othership_path):
    result["othership_exists"] = True
    try:
        with open(othership_path, 'r') as f:
            lines = f.readlines()
            
        # Parse indexed keys: Type(0)=..., InitialLat(0)=...
        objects = {}
        for line in lines:
            line = line.strip()
            # Match pattern Key(Index)=Value
            m = re.match(r'([a-zA-Z]+)\(([0-9]+)\)\s*=\s*(.*)', line)
            if m:
                key = m.group(1)
                idx = int(m.group(2))
                val = m.group(3).strip('"')
                
                if idx not in objects:
                    objects[idx] = {}
                
                # Convert numbers
                try:
                    objects[idx][key] = float(val)
                except ValueError:
                    objects[idx][key] = val
        
        # Convert dict to sorted list
        result["objects"] = [objects[i] for i in sorted(objects.keys())]
            
    except Exception as e:
        result["othership_error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

# Move to final location with permission handling
# The python script wrote directly to /tmp/task_result.json above
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="