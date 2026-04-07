#!/bin/bash
echo "=== Exporting MMO Calibration Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/m) MMO Calibration"
ENV_FILE="$SCENARIO_DIR/environment.ini"
OWN_FILE="$SCENARIO_DIR/ownship.ini"
OTHER_FILE="$SCENARIO_DIR/othership.ini"
CARD_FILE="/home/ga/Documents/calibration_card.txt"
EXPORT_JSON="/tmp/task_result.json"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Parse INI files and export to JSON using Python
# We use Python here to robustly parse the INI structure and handle the 'othership' indexed format
python3 -c "
import configparser
import json
import os
import re

result = {
    'files_exist': {
        'scenario_dir': os.path.isdir('$SCENARIO_DIR'),
        'environment': os.path.isfile('$ENV_FILE'),
        'ownship': os.path.isfile('$OWN_FILE'),
        'othership': os.path.isfile('$OTHER_FILE'),
        'card': os.path.isfile('$CARD_FILE')
    },
    'environment': {},
    'ownship': {},
    'targets': []
}

# Helper to read loose key=value files (Bridge Command INIs are not always strict INI)
def read_bc_ini(filepath):
    data = {}
    if not os.path.isfile(filepath):
        return data
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if '=' in line and not line.startswith(';'):
                key, val = line.split('=', 1)
                data[key.strip()] = val.strip().strip('\"')
    return data

# Parse Environment
result['environment'] = read_bc_ini('$ENV_FILE')

# Parse Ownship
result['ownship'] = read_bc_ini('$OWN_FILE')

# Parse Othership (Special Indexed Format)
# Bridge Command uses: Number=X, Type(1)=..., InitLat(1)=...
if os.path.isfile('$OTHER_FILE'):
    raw_other = read_bc_ini('$OTHER_FILE')
    count = int(raw_other.get('Number', 0))
    
    for i in range(1, count + 1):
        target = {
            'id': i,
            'type': raw_other.get(f'Type({i})'),
            'lat': raw_other.get(f'InitLat({i})'),
            'long': raw_other.get(f'InitLong({i})'),
            'speed': raw_other.get(f'Speed({i})', raw_other.get(f'InitialSpeed({i})')), # Sometimes varies
            'bearing': raw_other.get(f'InitialBearing({i})')
        }
        # Also check for leg format if InitialLat not used
        if not target['lat']:
            target['lat'] = raw_other.get(f'Leg(1)Lat({i})')
        if not target['long']:
            target['long'] = raw_other.get(f'Leg(1)Long({i})')
            
        result['targets'].append(target)

# Check Calibration Card
if result['files_exist']['card']:
    with open('$CARD_FILE', 'r') as f:
        result['card_content'] = f.read()

# Timestamps
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result['start_time'] = int(f.read().strip())
    
    if result['files_exist']['ownship']:
        result['file_mtime'] = int(os.path.getmtime('$OWN_FILE'))
    else:
        result['file_mtime'] = 0
except:
    result['start_time'] = 0
    result['file_mtime'] = 0

with open('$EXPORT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# 3. Secure the output
chmod 666 "$EXPORT_JSON" 2>/dev/null || true

echo "Export completed to $EXPORT_JSON"
cat "$EXPORT_JSON" 2>/dev/null || echo "Export failed"