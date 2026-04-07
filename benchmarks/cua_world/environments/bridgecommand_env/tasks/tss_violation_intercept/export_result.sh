#!/bin/bash
echo "=== Exporting TSS Violation Intercept Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/z) TSS Rogue Intercept"
BRIEFING_FILE="/home/ga/Documents/intercept_briefing.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || true

# Check if scenario directory exists
SCENARIO_EXISTS="false"
if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
fi

# Check if briefing exists and read content
BRIEFING_EXISTS="false"
BRIEFING_CONTENT=""
if [ -f "$BRIEFING_FILE" ]; then
    BRIEFING_EXISTS="true"
    BRIEFING_CONTENT=$(cat "$BRIEFING_FILE" | head -n 50) # Read first 50 lines
fi

# Helper python script to parse INI files accurately
# This is robust against whitespace and casing issues in INI files
python3 -c "
import configparser
import json
import os
import glob

result = {
    'scenario_exists': '$SCENARIO_EXISTS' == 'true',
    'briefing_exists': '$BRIEFING_EXISTS' == 'true',
    'briefing_content': '''$BRIEFING_CONTENT''',
    'environment': {},
    'ownship': {},
    'traffic': []
}

scenario_dir = '$SCENARIO_DIR'

def read_ini_loose(filepath):
    # Bridge Command INIs often lack section headers or use custom formats
    # We will try to read Key=Value lines manually for robustness
    data = {}
    if not os.path.exists(filepath):
        return data
    with open(filepath, 'r', errors='ignore') as f:
        for line in f:
            if '=' in line:
                parts = line.split('=', 1)
                key = parts[0].strip()
                val = parts[1].strip().strip('\"') # Remove quotes if present
                data[key] = val
    return data

# Parse environment.ini
env_path = os.path.join(scenario_dir, 'environment.ini')
result['environment'] = read_ini_loose(env_path)

# Parse ownship.ini
own_path = os.path.join(scenario_dir, 'ownship.ini')
result['ownship'] = read_ini_loose(own_path)

# Parse othership.ini
# othership.ini uses indexed keys like Type(1)=..., InitialLat(1)=...
other_path = os.path.join(scenario_dir, 'othership.ini')
raw_othership = read_ini_loose(other_path)

# Reconstruct vessel objects from indexed keys
vessels = {}
for key, value in raw_othership.items():
    if '(' in key and ')' in key:
        param_name = key.split('(')[0]
        try:
            index = int(key.split('(')[1].split(')')[0])
            if index not in vessels:
                vessels[index] = {}
            vessels[index][param_name] = value
        except:
            pass
    elif key == 'Number':
        result['traffic_count_declared'] = value

# Convert dict to list
result['traffic'] = [vessels[i] for i in sorted(vessels.keys())]

# Check file timestamps against task start
task_start = int('$TASK_START')
files_created_during_task = False
if result['scenario_exists']:
    try:
        # Check ownship.ini as a proxy
        mtime = os.path.getmtime(own_path)
        if mtime > task_start:
            files_created_during_task = True
    except:
        pass

result['files_created_during_task'] = files_created_during_task

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"