#!/bin/bash
echo "=== Exporting Legacy Scenario Migration Result ==="

SCENARIOS_DIR="/opt/bridgecommand/Scenarios"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to parse the INI files and output JSON
# We use Python because parsing INI files with loose formatting in bash is error-prone
python3 -c "
import os
import glob
import json
import re

base_dir = '$SCENARIOS_DIR'
results = {}

# Find folders starting with 'Migrated - '
migrated_dirs = glob.glob(os.path.join(base_dir, 'Migrated - *'))

for d in migrated_dirs:
    scenario_name = os.path.basename(d).replace('Migrated - ', '')
    scenario_data = {
        'exists': True,
        'environment_exists': os.path.exists(os.path.join(d, 'environment.ini')),
        'ownship': {},
        'othership': {}
    }

    # Parse ownship.ini
    own_path = os.path.join(d, 'ownship.ini')
    if os.path.exists(own_path):
        try:
            with open(own_path, 'r') as f:
                content = f.read()
                lat_match = re.search(r'InitialLat\s*=\s*([0-9.-]+)', content, re.IGNORECASE)
                long_match = re.search(r'InitialLong\s*=\s*([0-9.-]+)', content, re.IGNORECASE)
                if lat_match: scenario_data['ownship']['lat'] = float(lat_match.group(1))
                if long_match: scenario_data['ownship']['long'] = float(long_match.group(1))
        except Exception as e:
            scenario_data['ownship']['error'] = str(e)

    # Parse othership.ini
    other_path = os.path.join(d, 'othership.ini')
    if os.path.exists(other_path):
        try:
            with open(other_path, 'r') as f:
                content = f.read()
                # Find first vessel (index 1)
                type_match = re.search(r'Type\(1\)\s*=\s*[\"\'']?([^\"\'\r\n]+)[\"\'']?', content, re.IGNORECASE)
                lat_match = re.search(r'InitLat\(1\)\s*=\s*([0-9.-]+)', content, re.IGNORECASE)
                long_match = re.search(r'InitLong\(1\)\s*=\s*([0-9.-]+)', content, re.IGNORECASE)
                
                if type_match: scenario_data['othership']['type'] = type_match.group(1).strip()
                if lat_match: scenario_data['othership']['lat'] = float(lat_match.group(1))
                if long_match: scenario_data['othership']['long'] = float(long_match.group(1))
        except Exception as e:
            scenario_data['othership']['error'] = str(e)
            
    results[scenario_name] = scenario_data

output = {
    'migrated_scenarios': results,
    'timestamp': '$TASK_START'
}

print(json.dumps(output, indent=2))
" > /tmp/task_result.json

# Fix permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="