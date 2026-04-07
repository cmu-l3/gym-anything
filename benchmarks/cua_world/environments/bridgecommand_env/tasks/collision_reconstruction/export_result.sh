#!/bin/bash
echo "=== Exporting collision_reconstruction result ==="

# Define paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/n) Solent Collision Reconstruction"
REPORT_FILE="/home/ga/Documents/incident_analysis_report.txt"
BC_CONFIG_USER="/home/ga/.config/Bridge Command/bc5.ini"
BC_CONFIG_DATA="/opt/bridgecommand/bc5.ini"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to parse INI files and generate JSON result
# We use Python here because bash parsing of INI files (especially indexed ones) is fragile
python3 -c "
import configparser
import json
import os
import glob
import re
import sys

# Helper to read 'flat' INI files (environment.ini, ownship.ini)
# Note: BC INI files often don't have sections, or have implicit sections.
# We'll treat them as properties files if configparser fails without headers.
def read_ini(filepath):
    if not os.path.exists(filepath):
        return None
    
    # Try reading as raw lines first to handle key=value pairs without sections
    data = {}
    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if '=' in line and not line.startswith(';'):
                    key, val = line.split('=', 1)
                    # Remove quotes if present
                    val = val.strip().strip('\"')
                    data[key.strip()] = val
    except Exception as e:
        return {'error': str(e)}
    return data

# Helper to read 'othership.ini' which uses Key(N)=Value format
def read_othership(filepath):
    if not os.path.exists(filepath):
        return None
    
    vessels = []
    vessel_map = {} # Map index to dict
    
    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                # Match pattern: Key(Index)=Value
                # e.g. Type(1)=\"Ferry\"
                m = re.match(r'([A-Za-z]+)\(([0-9]+)\)=(.*)', line)
                if m:
                    key = m.group(1)
                    idx = int(m.group(2))
                    val = m.group(3).strip().strip('\"')
                    
                    if idx not in vessel_map:
                        vessel_map[idx] = {}
                    vessel_map[idx][key] = val
                    
        # Convert map to list
        for idx in sorted(vessel_map.keys()):
            vessels.append(vessel_map[idx])
            
    except Exception as e:
        return {'error': str(e)}
    return vessels

# Helper to read bc5.ini (standard INI format)
def read_config(filepath):
    if not os.path.exists(filepath):
        return {}
    config = configparser.ConfigParser()
    try:
        config.read(filepath)
        return {s: dict(config.items(s)) for s in config.sections()}
    except:
        # Fallback to simple line reading if structure is messy
        return read_ini(filepath)

# --- Gather Data ---

result = {
    'scenario_exists': os.path.isdir('$SCENARIO_DIR'),
    'files': {},
    'config': {},
    'report': {}
}

# 1. Parse Scenario Files
if result['scenario_exists']:
    result['files']['environment'] = read_ini(os.path.join('$SCENARIO_DIR', 'environment.ini'))
    result['files']['ownship'] = read_ini(os.path.join('$SCENARIO_DIR', 'ownship.ini'))
    result['files']['othership'] = read_othership(os.path.join('$SCENARIO_DIR', 'othership.ini'))
    
    # Check timestamps
    try:
        mtime = os.path.getmtime('$SCENARIO_DIR')
        result['scenario_created_after_start'] = mtime > $TASK_START_TIME
    except:
        result['scenario_created_after_start'] = False

# 2. Parse BC Configuration (Check both locations)
# Merge them, giving priority to user config
sys_conf = read_config('$BC_CONFIG_DATA')
user_conf = read_config('$BC_CONFIG_USER')

# Flatten config for easier verification (Settings are usually unique keys)
merged_config = {}
def flatten(d):
    for k, v in d.items():
        if isinstance(v, dict):
            for sk, sv in v.items():
                merged_config[sk.lower()] = sv # Lowercase keys for robust matching
        else:
            merged_config[k.lower()] = v

flatten(sys_conf)
flatten(user_conf)
result['config'] = merged_config

# 3. Read Report
if os.path.exists('$REPORT_FILE'):
    try:
        with open('$REPORT_FILE', 'r', errors='ignore') as f:
            content = f.read()
        result['report']['exists'] = True
        result['report']['content'] = content
        result['report']['length'] = len(content)
        result['report']['created_after_start'] = os.path.getmtime('$REPORT_FILE') > $TASK_START_TIME
    except Exception as e:
        result['report']['error'] = str(e)
else:
    result['report']['exists'] = False

# Save JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="