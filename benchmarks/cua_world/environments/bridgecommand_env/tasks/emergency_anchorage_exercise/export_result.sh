#!/bin/bash
echo "=== Exporting Emergency Anchorage Exercise Results ==="

# Define paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/n) Cowes Roads Emergency Anchorage"
DOC_FILE="/home/ga/Documents/anchorage_approach_plan.txt"
BC_CONFIG_USER="/home/ga/.config/Bridge Command/bc5.ini"
BC_CONFIG_DATA="/opt/bridgecommand/bc5.ini"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Take final screenshot for visual verification
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- Gather Data ---

# 1. Check Scenario Existence & Files
SCENARIO_EXISTS=false
ENV_EXISTS=false
OWNSHIP_EXISTS=false
OTHERSHIP_EXISTS=false
[ -d "$SCENARIO_DIR" ] && SCENARIO_EXISTS=true
[ -f "$SCENARIO_DIR/environment.ini" ] && ENV_EXISTS=true
[ -f "$SCENARIO_DIR/ownship.ini" ] && OWNSHIP_EXISTS=true
[ -f "$SCENARIO_DIR/othership.ini" ] && OTHERSHIP_EXISTS=true

# 2. Parse INI Files (Python is safer for loose INI formats)
# We embed a python script to parse the INI files and output a JSON structure
python3 -c "
import configparser
import json
import os
import re

def parse_bc_ini(filepath):
    # Bridge Command INI files are often just Key=Value lines, sometimes without headers
    # except bc5.ini which has [Sections]
    data = {}
    if not os.path.exists(filepath):
        return data
    
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()

    # Simple key=value parser for scenario files
    for line in lines:
        line = line.strip()
        if not line or line.startswith(';'): continue
        if '=' in line:
            parts = line.split('=', 1)
            key = parts[0].strip()
            val = parts[1].strip().strip('\"')
            data[key] = val
    return data

def parse_bc5_ini(filepath):
    # Use ConfigParser for bc5.ini as it has sections
    config = configparser.ConfigParser()
    config.read(filepath)
    data = {}
    for section in config.sections():
        for key in config[section]:
            data[key] = config[section][key]
    return data

result = {
    'scenario_found': $SCENARIO_EXISTS,
    'files': {
        'environment': $ENV_EXISTS,
        'ownship': $OWNSHIP_EXISTS,
        'othership': $OTHERSHIP_EXISTS
    },
    'env_data': parse_bc_ini('$SCENARIO_DIR/environment.ini'),
    'ownship_data': parse_bc_ini('$SCENARIO_DIR/ownship.ini'),
    'othership_data': parse_bc_ini('$SCENARIO_DIR/othership.ini'),
    'bc5_user': parse_bc5_ini('$BC_CONFIG_USER'),
    'bc5_data': parse_bc5_ini('$BC_CONFIG_DATA')
}

# 3. Parse Document
doc_path = '$DOC_FILE'
doc_content = ''
doc_exists = False
doc_created_during_task = False

if os.path.exists(doc_path):
    doc_exists = True
    # Check timestamp
    mtime = os.path.getmtime(doc_path)
    if mtime > float($TASK_START_TIME):
        doc_created_during_task = True
    
    try:
        with open(doc_path, 'r') as f:
            doc_content = f.read()
    except:
        doc_content = 'Error reading file'

result['document'] = {
    'exists': doc_exists,
    'created_during_task': doc_created_during_task,
    'content': doc_content,
    'length': len(doc_content)
}

# 4. Extract vessel details specifically (for verifying anchors etc)
# Bridge Command othership.ini uses indexed keys like Speed(1)=...
vessels = []
othership = result['othership_data']
num_vessels = int(othership.get('Number', 0))

for i in range(1, num_vessels + 1):
    v = {}
    idx = str(i)
    v['type'] = othership.get(f'Type({idx})', '')
    v['speed'] = float(othership.get(f'InitialSpeed({idx})', -1))
    v['lat'] = float(othership.get(f'InitialLat({idx})', 0))
    v['long'] = float(othership.get(f'InitialLong({idx})', 0))
    vessels.append(v)

result['vessels_parsed'] = vessels

# Dump result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print('Export successful.')
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="