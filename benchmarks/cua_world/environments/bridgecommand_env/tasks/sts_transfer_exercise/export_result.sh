#!/bin/bash
echo "=== Exporting STS Transfer Exercise Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/n) Solent STS Transfer Exercise"
BRIEFING_FILE="/home/ga/Documents/sts_operation_briefing.txt"
BC_CONFIG_LOCATIONS=(
    "/home/ga/.config/Bridge Command/bc5.ini"
    "/opt/bridgecommand/bc5.ini"
    "/home/ga/.Bridge Command/5.10/bc5.ini"
)

# 1. Timestamp checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 2. Capture final screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || true

# 3. Python script to parse the INI files (Bridge Command format is tricky for bash)
# It will output a JSON structure with all the data needed for verification
python3 -c "
import json
import os
import configparser
import re

result = {
    'task_start': $TASK_START,
    'export_time': $CURRENT_TIME,
    'scenario_dir_exists': False,
    'files_exist': {
        'environment': False,
        'ownship': False,
        'othership': False,
        'briefing': False
    },
    'environment': {},
    'ownship': {},
    'otherships': [],
    'config': {},
    'briefing_content': ''
}

scenario_dir = '$SCENARIO_DIR'
if os.path.isdir(scenario_dir):
    result['scenario_dir_exists'] = True
    
    # Parse environment.ini (Flat key=value)
    env_path = os.path.join(scenario_dir, 'environment.ini')
    if os.path.exists(env_path):
        result['files_exist']['environment'] = True
        try:
            with open(env_path, 'r') as f:
                for line in f:
                    if '=' in line:
                        k, v = line.strip().split('=', 1)
                        result['environment'][k.strip()] = v.strip().strip('\"')
        except Exception as e:
            result['environment_error'] = str(e)

    # Parse ownship.ini (Flat key=value)
    own_path = os.path.join(scenario_dir, 'ownship.ini')
    if os.path.exists(own_path):
        result['files_exist']['ownship'] = True
        try:
            with open(own_path, 'r') as f:
                for line in f:
                    if '=' in line:
                        k, v = line.strip().split('=', 1)
                        result['ownship'][k.strip()] = v.strip().strip('\"')
        except Exception as e:
            result['ownship_error'] = str(e)

    # Parse othership.ini (Indexed Key(N)=Value)
    other_path = os.path.join(scenario_dir, 'othership.ini')
    if os.path.exists(other_path):
        result['files_exist']['othership'] = True
        vessels = {}
        try:
            with open(other_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line or '=' not in line: continue
                    
                    key_part, val = line.split('=', 1)
                    val = val.strip().strip('\"')
                    
                    # Extract index from Key(N)
                    match = re.match(r'([a-zA-Z]+)\((\d+)\)', key_part)
                    if match:
                        param = match.group(1)
                        idx = int(match.group(2))
                        if idx not in vessels: vessels[idx] = {}
                        vessels[idx][param] = val
                    elif key_part == 'Number':
                         result['othership_count_declared'] = val
            
            # Convert dict to list
            result['otherships'] = [vessels[k] for k in sorted(vessels.keys())]
        except Exception as e:
             result['othership_error'] = str(e)

# Parse bc5.ini (Standard INI section format)
# We check all locations and merge, giving priority to user config
config_data = {}
locations = [
    '/opt/bridgecommand/bc5.ini',
    '/home/ga/.config/Bridge Command/bc5.ini',
    '/home/ga/.Bridge Command/5.10/bc5.ini'
]

for loc in locations:
    if os.path.exists(loc):
        try:
            # Simple manual parse to avoid ConfigParser issues with duplicate keys/no headers
            with open(loc, 'r') as f:
                for line in f:
                    if '=' in line:
                        k, v = line.strip().split('=', 1)
                        config_data[k.strip()] = v.strip().strip('\"')
        except:
            pass
result['config'] = config_data

# Read Briefing Document
briefing_path = '$BRIEFING_FILE'
if os.path.exists(briefing_path):
    result['files_exist']['briefing'] = True
    result['briefing_mtime'] = os.path.getmtime(briefing_path)
    try:
        with open(briefing_path, 'r', errors='ignore') as f:
            result['briefing_content'] = f.read()
    except:
        result['briefing_content'] = ''

# Save JSON
with open('/tmp/sts_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 4. Secure the result file
cp /tmp/sts_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json