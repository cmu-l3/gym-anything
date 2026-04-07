#!/bin/bash
echo "=== Exporting IAMSAR Search Pattern Result ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/s) SAR Expanding Square"
PLAN_FILE="/home/ga/Documents/search_action_plan.txt"
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper function to check file existence
check_file() {
    if [ -f "$1" ]; then echo "true"; else echo "false"; fi
}

SCENARIO_EXISTS=$(if [ -d "$SCENARIO_DIR" ]; then echo "true"; else echo "false"; fi)
ENV_EXISTS=$(check_file "$SCENARIO_DIR/environment.ini")
OWN_EXISTS=$(check_file "$SCENARIO_DIR/ownship.ini")
OTHER_EXISTS=$(check_file "$SCENARIO_DIR/othership.ini")
PLAN_EXISTS=$(check_file "$PLAN_FILE")

# Use Python to parse the INI files and Plan file into a robust JSON structure
# This avoids fragile bash parsing of INI formats
python3 -c "
import json
import os
import configparser
import re

def parse_ini_loose(filepath):
    """Parse INI file allowing for loose syntax (keys without sections sometimes used in BC)"""
    data = {}
    if not os.path.exists(filepath):
        return data
    
    # Bridge Command INI files are sometimes flat Key=Value without headers
    # We'll treat them as a dummy section
    with open(filepath, 'r') as f:
        content = f.read()
    
    # Add dummy header if none exists
    if not content.strip().startswith('['):
        content = '[DEFAULT]\n' + content
        
    cp = configparser.ConfigParser()
    try:
        cp.read_string(content)
        # Flatten structure
        for sec in cp.sections():
            for k, v in cp.items(sec):
                data[k] = v
        for k, v in cp.items('DEFAULT'):
            data[k] = v
    except:
        # Fallback regex parsing if ConfigParser fails
        with open(filepath, 'r') as f:
            for line in f:
                if '=' in line:
                    key, val = line.split('=', 1)
                    data[key.strip().lower()] = val.strip().strip('\"')
    return data

result = {
    'scenario_exists': '$SCENARIO_EXISTS' == 'true',
    'files': {
        'environment': '$ENV_EXISTS' == 'true',
        'ownship': '$OWN_EXISTS' == 'true',
        'othership': '$OTHER_EXISTS' == 'true',
        'plan': '$PLAN_EXISTS' == 'true'
    },
    'environment_data': parse_ini_loose('$SCENARIO_DIR/environment.ini'),
    'ownship_data': parse_ini_loose('$SCENARIO_DIR/ownship.ini'),
    'othership_data': parse_ini_loose('$SCENARIO_DIR/othership.ini'),
    'plan_content': ''
}

# Read Plan content
if result['files']['plan']:
    try:
        with open('$PLAN_FILE', 'r') as f:
            result['plan_content'] = f.read()[:5000]
    except:
        pass

# Extract Legs specifically from ownship to list
legs = []
own = result['ownship_data']
# Find max leg index
max_leg = 0
for k in own.keys():
    if k.startswith('leg(') and 'lat' in k:
        try:
            idx = int(re.search(r'leg\((\d+)\)', k).group(1))
            if idx > max_leg: max_leg = idx
        except:
            pass

for i in range(1, max_leg + 1):
    leg = {}
    leg['lat'] = own.get(f'leg({i})lat')
    leg['long'] = own.get(f'leg({i})long')
    leg['speed'] = own.get(f'leg({i})speed')
    if leg['lat']:
        legs.append(leg)

result['ownship_legs'] = legs

with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so verifier can read it
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"