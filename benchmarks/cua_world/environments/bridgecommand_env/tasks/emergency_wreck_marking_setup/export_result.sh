#!/bin/bash
echo "=== Exporting Emergency Wreck Marking Results ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/z) Wreck of MV Meridian"
OTHERSHIP_FILE="$SCENARIO_DIR/othership.ini"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if scenario directory was created
if [ -d "$SCENARIO_DIR" ]; then
    DIR_EXISTS="true"
else
    DIR_EXISTS="false"
fi

# 2. Check if othership.ini exists and was created during task
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OTHERSHIP_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OTHERSHIP_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Capture screenshot of the directory listing (evidence of work)
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || true

# 4. Parse othership.ini into JSON
# This is complex because Bridge Command uses an indexed INI format (Key(1)=Val, Key(2)=Val)
# We use Python to parse it robustly.

cat << 'PYEOF' > /tmp/parse_othership.py
import sys
import json
import re

file_path = sys.argv[1]
output_path = sys.argv[2]
task_start = int(sys.argv[3])
dir_exists = sys.argv[4] == "true"
file_exists = sys.argv[5] == "true"
created_during = sys.argv[6] == "true"

vessels = []

if file_exists:
    try:
        with open(file_path, 'r') as f:
            content = f.read()
            
        # Regex to match indexed keys like InitialLat(1)=50.7
        # We store raw data first
        raw_data = {}
        for line in content.splitlines():
            line = line.strip()
            if '=' in line and not line.startswith(';'):
                key, val = line.split('=', 1)
                key = key.strip()
                val = val.strip().strip('"') # Remove quotes if present
                
                # Parse index like Type(1)
                match = re.match(r'([a-zA-Z]+)\((\d+)\)', key)
                if match:
                    param = match.group(1)
                    idx = int(match.group(2))
                    if idx not in raw_data:
                        raw_data[idx] = {}
                    raw_data[idx][param] = val
                elif key == "Number":
                    # Global key, ignore for individual object parsing
                    pass

        # Convert to list
        for idx in sorted(raw_data.keys()):
            v = raw_data[idx]
            vessels.append({
                "index": idx,
                "type": v.get("Type", "unknown"),
                "lat": float(v.get("InitialLat", 0.0)),
                "long": float(v.get("InitialLong", 0.0))
            })
            
    except Exception as e:
        print(f"Error parsing INI: {e}", file=sys.stderr)

result = {
    "directory_exists": dir_exists,
    "file_exists": file_exists,
    "file_created_during_task": created_during,
    "vessels": vessels,
    "vessel_count": len(vessels)
}

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

python3 /tmp/parse_othership.py "$OTHERSHIP_FILE" "/tmp/task_result.json" "$TASK_START" "$DIR_EXISTS" "$FILE_EXISTS" "$FILE_CREATED_DURING_TASK"

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json