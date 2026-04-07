#!/bin/bash
echo "=== Exporting Historical Battle Reconstruction Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SCENARIO_DIR="/opt/bridgecommand/Scenarios/h) River Plate 1939"
CALC_FILE="/home/ga/Documents/battle_calculations.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check if scenario directory exists
if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
else
    SCENARIO_EXISTS="false"
fi

# 2. Check if calculations file exists and was created during task
CALC_FILE_EXISTS="false"
CALC_FILE_FRESH="false"
if [ -f "$CALC_FILE" ]; then
    CALC_FILE_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$CALC_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CALC_FILE_FRESH="true"
    fi
fi

# 3. Parse INI files if they exist
# We use a Python one-liner to parse the INI structure safely and export to JSON
# This handles the tricky 'Key(N)=Value' format of othership.ini

python3 -c "
import configparser
import json
import os
import re

result = {
    'scenario_exists': '$SCENARIO_EXISTS' == 'true',
    'calc_file_exists': '$CALC_FILE_EXISTS' == 'true',
    'calc_file_fresh': '$CALC_FILE_FRESH' == 'true',
    'files': {
        'environment': False,
        'ownship': False,
        'othership': False
    },
    'data': {
        'environment': {},
        'ownship': {},
        'othership': []
    }
}

scenario_dir = '$SCENARIO_DIR'

def clean_ini_content(content):
    # Bridge Command INIs sometimes lack section headers or have duplicates
    # We'll artificially add a section header if missing to make configparser happy
    if not content.strip().startswith('['):
        return '[General]\n' + content
    return content

# Parse environment.ini
env_path = os.path.join(scenario_dir, 'environment.ini')
if os.path.exists(env_path):
    result['files']['environment'] = True
    try:
        with open(env_path, 'r') as f:
            content = clean_ini_content(f.read())
        config = configparser.ConfigParser(strict=False)
        config.read_string(content)
        if 'General' in config:
            result['data']['environment'] = dict(config['General'])
    except Exception as e:
        result['data']['environment_error'] = str(e)

# Parse ownship.ini
own_path = os.path.join(scenario_dir, 'ownship.ini')
if os.path.exists(own_path):
    result['files']['ownship'] = True
    try:
        with open(own_path, 'r') as f:
            content = clean_ini_content(f.read())
        config = configparser.ConfigParser(strict=False)
        config.read_string(content)
        if 'General' in config:
            result['data']['ownship'] = dict(config['General'])
    except Exception as e:
        result['data']['ownship_error'] = str(e)

# Parse othership.ini (Custom parser for indexed keys)
other_path = os.path.join(scenario_dir, 'othership.ini')
if os.path.exists(other_path):
    result['files']['othership'] = True
    try:
        with open(other_path, 'r') as f:
            lines = f.readlines()
        
        vessels = {}
        for line in lines:
            line = line.strip()
            # Match pattern like Key(Index)=Value
            m = re.match(r'([A-Za-z]+)\((\d+)\)=(.*)', line)
            if m:
                key, idx, val = m.groups()
                idx = int(idx)
                if idx not in vessels:
                    vessels[idx] = {}
                vessels[idx][key.lower()] = val.strip().strip('\"')
        
        # Convert dict to list
        result['data']['othership'] = [vessels[i] for i in sorted(vessels.keys())]
        
    except Exception as e:
        result['data']['othership_error'] = str(e)

print(json.dumps(result))
" > /tmp/parsed_result.json

# Move result to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/parsed_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="