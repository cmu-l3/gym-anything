#!/bin/bash
echo "=== Exporting Asymmetric Threat Intercept Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/n) Swarm Attack Drill"
CALC_FILE="/home/ga/Documents/intercept_calculations.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check if Scenario Exists
SCENARIO_EXISTS="false"
FILES_EXIST="false"
if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
    if [ -f "$SCENARIO_DIR/ownship.ini" ] && [ -f "$SCENARIO_DIR/othership.ini" ]; then
        FILES_EXIST="true"
    fi
fi

# 2. Check file modification times (Anti-gaming)
FILES_CREATED_DURING_TASK="false"
if [ "$FILES_EXIST" = "true" ]; then
    OWN_MTIME=$(stat -c %Y "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "0")
    OTHER_MTIME=$(stat -c %Y "$SCENARIO_DIR/othership.ini" 2>/dev/null || echo "0")
    
    if [ "$OWN_MTIME" -gt "$TASK_START" ] && [ "$OTHER_MTIME" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
fi

# 3. Parse INI files using Python to extract kinematic data
# We embed a python script to handle the messy INI parsing and coordinate extraction
python3 -c "
import sys
import os
import json
import configparser
import math

def parse_ini_file(filepath):
    # Bridge Command INI files often don't have section headers or use duplicates
    # We'll parse manually to be robust against 'Key(Index)=Value' format
    data = {}
    if not os.path.exists(filepath):
        return data
        
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(';'):
                continue
            if '=' in line:
                key, value = line.split('=', 1)
                data[key.strip()] = value.strip().replace('\"', '')
    return data

result = {
    'scenario_found': '$SCENARIO_EXISTS' == 'true',
    'files_valid': '$FILES_EXIST' == 'true',
    'created_during_task': '$FILES_CREATED_DURING_TASK' == 'true',
    'ownship': {},
    'skiffs': [],
    'calculations_file_exists': os.path.exists('$CALC_FILE')
}

if result['files_valid']:
    # Parse Ownship
    own_data = parse_ini_file('$SCENARIO_DIR/ownship.ini')
    result['ownship'] = {
        'lat': float(own_data.get('InitialLat', 0)),
        'long': float(own_data.get('InitialLong', 0)),
        'speed': float(own_data.get('InitialSpeed', 0)),
        'bearing': float(own_data.get('InitialBearing', 0)),
        'name': own_data.get('ShipName', '')
    }
    
    # Parse Othership (Skiffs)
    # othership.ini uses indexed keys like InitialLat(1)=...
    other_data = parse_ini_file('$SCENARIO_DIR/othership.ini')
    
    # Find all indices
    indices = set()
    for key in other_data.keys():
        if '(' in key and ')' in key:
            try:
                idx = int(key.split('(')[1].split(')')[0])
                indices.add(idx)
            except:
                pass
                
    for idx in sorted(list(indices)):
        skiff = {
            'id': idx,
            'lat': float(other_data.get(f'InitialLat({idx})', -999)),
            'long': float(other_data.get(f'InitialLong({idx})', -999)),
            'speed': float(other_data.get(f'InitialSpeed({idx})', 0)),
            # Try to get type/name if available
            'type': other_data.get(f'Type({idx})', 'unknown')
        }
        # Only add valid entries
        if skiff['lat'] != -999:
            result['skiffs'].append(skiff)

# Write to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="