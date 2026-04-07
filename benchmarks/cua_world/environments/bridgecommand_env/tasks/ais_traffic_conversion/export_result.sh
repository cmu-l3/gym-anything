#!/bin/bash
echo "=== Exporting AIS Traffic Conversion Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/p) Solent AIS Traffic 20231015"
CONFIG_FILE="/home/ga/.config/Bridge Command/bc5.ini"
REPORT_FILE="/home/ga/Documents/ais_data/conversion_report.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to robustly parse the INI files and export JSON
python3 -c "
import configparser
import json
import os
import glob
import re
import sys

def parse_bc_ini(filepath):
    # Bridge Command INI files often lack section headers or have duplicates
    # We'll use a custom parser for othership.ini complexity
    data = {}
    if not os.path.exists(filepath):
        return data
    
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
        
    for line in lines:
        line = line.strip()
        if '=' in line and not line.startswith(';'):
            key, val = line.split('=', 1)
            key = key.strip()
            val = val.strip().strip('\"')
            
            # Handle array-like keys: Type(1), InitLat(1), Leg(1,1)
            if '(' in key and ')' in key:
                main_key = key.split('(')[0]
                indices = key.split('(')[1].split(')')[0]
                
                if main_key not in data:
                    data[main_key] = {}
                
                data[main_key][indices] = val
            else:
                data[key] = val
    return data

result = {
    'scenario_dir_exists': os.path.isdir('$SCENARIO_DIR'),
    'files': {
        'environment': os.path.exists(os.path.join('$SCENARIO_DIR', 'environment.ini')),
        'ownship': os.path.exists(os.path.join('$SCENARIO_DIR', 'ownship.ini')),
        'othership': os.path.exists(os.path.join('$SCENARIO_DIR', 'othership.ini')),
        'report': os.path.exists('$REPORT_FILE')
    },
    'environment': {},
    'ownship': {},
    'othership': {},
    'config': {},
    'report_content': ''
}

# Parse Scenario Files
if result['scenario_dir_exists']:
    result['environment'] = parse_bc_ini(os.path.join('$SCENARIO_DIR', 'environment.ini'))
    result['ownship'] = parse_bc_ini(os.path.join('$SCENARIO_DIR', 'ownship.ini'))
    result['othership'] = parse_bc_ini(os.path.join('$SCENARIO_DIR', 'othership.ini'))

# Parse Config
result['config'] = parse_bc_ini('$CONFIG_FILE')

# Read Report
if result['files']['report']:
    with open('$REPORT_FILE', 'r', errors='ignore') as f:
        result['report_content'] = f.read()

# Anti-gaming: Check timestamps
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = int(f.read().strip())
        
    def check_mtime(path):
        if os.path.exists(path):
            return os.path.getmtime(path) > start_time
        return False

    result['timestamps'] = {
        'othership': check_mtime(os.path.join('$SCENARIO_DIR', 'othership.ini')),
        'report': check_mtime('$REPORT_FILE'),
        'config': check_mtime('$CONFIG_FILE')
    }
except Exception as e:
    result['timestamps_error'] = str(e)

# Save Result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print('Export JSON created at /tmp/task_result.json')
"

# Copy to location accessible by verification host (handled by framework if using copy_from_env)
# But we ensure it's readable
chmod 644 /tmp/task_result.json

echo "=== Export Complete ==="