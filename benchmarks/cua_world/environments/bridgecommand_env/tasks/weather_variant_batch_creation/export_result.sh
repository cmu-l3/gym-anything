#!/bin/bash
echo "=== Exporting Meteorological Variant Task Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios"
MANIFEST_PATH="/home/ga/Documents/scenario_manifest.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BASE_SPEED_TRUTH=$(cat /tmp/base_speed_truth.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper python script to parse INI values robustly
# Bridge Command INI files are simple Key=Value pairs
parse_ini() {
    local file="$1"
    local key="$2"
    if [ -f "$file" ]; then
        grep -i "^$key=" "$file" | cut -d'=' -f2 | tr -d '\r' | head -1
    else
        echo ""
    fi
}

# Python script to build the JSON result
# We use python to handle the looping and JSON construction cleanly
python3 -c "
import json
import os
import csv
import time

base_dir = '$SCENARIO_DIR'
variants = [
    '01_Assessment_Clear',
    '02_Assessment_Haze',
    '03_Assessment_Fog',
    '04_Assessment_Storm'
]

result = {
    'task_start': $TASK_START,
    'base_speed_truth': '$BASE_SPEED_TRUTH',
    'manifest_exists': False,
    'manifest_content': [],
    'variants': {}
}

# Check Manifest
manifest_path = '$MANIFEST_PATH'
if os.path.exists(manifest_path):
    result['manifest_exists'] = True
    try:
        with open(manifest_path, 'r') as f:
            result['manifest_content'] = f.read().strip().split('\n')
    except:
        pass

# Check Variants
for v_name in variants:
    v_path = os.path.join(base_dir, v_name)
    v_data = {
        'exists': False,
        'created_during_task': False,
        'environment': {},
        'ownship': {},
        'briefing': {'exists': False, 'content': ''}
    }
    
    if os.path.isdir(v_path):
        v_data['exists'] = True
        
        # Check timestamp of directory
        mtime = os.stat(v_path).st_mtime
        if mtime > $TASK_START:
            v_data['created_during_task'] = True

        # Parse environment.ini
        env_file = os.path.join(v_path, 'environment.ini')
        if os.path.exists(env_file):
            with open(env_file, 'r') as f:
                for line in f:
                    if '=' in line:
                        k, v = line.strip().split('=', 1)
                        v_data['environment'][k.strip()] = v.strip()

        # Parse ownship.ini
        own_file = os.path.join(v_path, 'ownship.ini')
        if os.path.exists(own_file):
            with open(own_file, 'r') as f:
                for line in f:
                    if '=' in line:
                        k, v = line.strip().split('=', 1)
                        v_data['ownship'][k.strip()] = v.strip()
        
        # Check Briefing
        briefing_file = os.path.join(v_path, 'briefing.txt')
        if os.path.exists(briefing_file):
            v_data['briefing']['exists'] = True
            with open(briefing_file, 'r') as f:
                v_data['briefing']['content'] = f.read().strip()

    result['variants'][v_name] = v_data

# Write to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="