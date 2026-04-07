#!/bin/bash
echo "=== Exporting Spithead Fleet Review Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/r) Spithead Fleet Review"
SCHEDULE_FILE="/home/ga/Documents/review_schedule.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper function to check if file was modified during task
check_file_modified() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

SCENARIO_CREATED=$(check_file_modified "$SCENARIO_DIR/ownship.ini")
SCHEDULE_CREATED=$(check_file_modified "$SCHEDULE_FILE")

# Use Python to robustly parse the INI files (especially indexed keys like Lat(1))
# and the text schedule, then output JSON.
python3 -c "
import configparser
import json
import os
import re
import glob

result = {
    'scenario_exists': False,
    'files_created_during_task': {
        'scenario': $SCENARIO_CREATED,
        'schedule': $SCHEDULE_CREATED
    },
    'ownship': {},
    'fleet': [],
    'schedule_content': [],
    'errors': []
}

scenario_dir = '$SCENARIO_DIR'
schedule_file = '$SCHEDULE_FILE'

# --- Parse Scenario Files ---
if os.path.isdir(scenario_dir):
    result['scenario_exists'] = True
    
    # 1. Parse Ownship
    own_path = os.path.join(scenario_dir, 'ownship.ini')
    if os.path.exists(own_path):
        try:
            with open(own_path, 'r') as f:
                content = '[root]\n' + f.read()
            config = configparser.ConfigParser()
            config.read_string(content)
            if 'root' in config:
                result['ownship'] = {k: v for k, v in config['root'].items()}
        except Exception as e:
            result['errors'].append(f'Error parsing ownship.ini: {str(e)}')

    # 2. Parse Othership (The Fleet)
    other_path = os.path.join(scenario_dir, 'othership.ini')
    if os.path.exists(other_path):
        try:
            # Bridge Command indexed ini files are weird. 
            # Format: Lat(1)=X, Lat(2)=Y.
            # We'll parse manually or regex.
            with open(other_path, 'r') as f:
                raw_lines = f.readlines()
            
            ships = {}
            for line in raw_lines:
                line = line.strip()
                if '=' not in line: continue
                key, val = line.split('=', 1)
                key = key.strip()
                val = val.strip().strip('\"')
                
                # Regex to match Key(Index)
                m = re.match(r'([A-Za-z]+)\((\d+)\)', key)
                if m:
                    param, idx = m.groups()
                    idx = int(idx)
                    if idx not in ships: ships[idx] = {'index': idx}
                    ships[idx][param.lower()] = val
            
            # Convert dict to sorted list
            result['fleet'] = [ships[i] for i in sorted(ships.keys())]
            
        except Exception as e:
            result['errors'].append(f'Error parsing othership.ini: {str(e)}')

# --- Parse Schedule File ---
if os.path.exists(schedule_file):
    try:
        with open(schedule_file, 'r') as f:
            result['schedule_content'] = [l.strip() for l in f.readlines() if l.strip()]
    except Exception as e:
         result['errors'].append(f'Error reading schedule: {str(e)}')

# Output JSON
print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# Permission fix for verifier
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json