#!/bin/bash
echo "=== Exporting Fisheries Patrol Result ==="

# Bridge Command paths
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/p) Solent Fisheries Patrol"
BRIEFING_FILE="/home/ga/Documents/fisheries_patrol_briefing.txt"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use embedded Python to parse INI files robustly (handling flat vs indexed keys)
# and generate a comprehensive JSON result file.
python3 -c "
import os
import sys
import json
import configparser
import re
import glob

result = {
    'scenario_dir_exists': False,
    'files': {},
    'scenario_data': {
        'environment': {},
        'ownship': {},
        'othership': {'vessels': []}
    },
    'radar_config': {},
    'briefing': {'exists': False, 'content': '', 'mtime': 0},
    'timestamps': {'task_start': $TASK_START_TIME}
}

scenario_dir = '$SCENARIO_DIR'
briefing_file = '$BRIEFING_FILE'

# 1. Check Scenario Files
if os.path.isdir(scenario_dir):
    result['scenario_dir_exists'] = True
    
    # Parse environment.ini (Flat Key=Value)
    env_path = os.path.join(scenario_dir, 'environment.ini')
    if os.path.exists(env_path):
        result['files']['environment.ini'] = {'exists': True, 'mtime': os.path.getmtime(env_path)}
        try:
            with open(env_path, 'r', errors='ignore') as f:
                for line in f:
                    if '=' in line:
                        k, v = line.split('=', 1)
                        result['scenario_data']['environment'][k.strip()] = v.strip().strip('\"')
        except Exception as e:
            result['files']['environment.ini']['error'] = str(e)
    else:
        result['files']['environment.ini'] = {'exists': False}

    # Parse ownship.ini (Flat Key=Value)
    own_path = os.path.join(scenario_dir, 'ownship.ini')
    if os.path.exists(own_path):
        result['files']['ownship.ini'] = {'exists': True, 'mtime': os.path.getmtime(own_path)}
        try:
            with open(own_path, 'r', errors='ignore') as f:
                for line in f:
                    if '=' in line:
                        k, v = line.split('=', 1)
                        result['scenario_data']['ownship'][k.strip()] = v.strip().strip('\"')
        except Exception as e:
            result['files']['ownship.ini']['error'] = str(e)
    else:
        result['files']['ownship.ini'] = {'exists': False}

    # Parse othership.ini (Indexed Key(N)=Value)
    other_path = os.path.join(scenario_dir, 'othership.ini')
    if os.path.exists(other_path):
        result['files']['othership.ini'] = {'exists': True, 'mtime': os.path.getmtime(other_path)}
        try:
            vessels = {}
            with open(other_path, 'r', errors='ignore') as f:
                for line in f:
                    line = line.strip()
                    if '=' not in line: continue
                    
                    key_part, val = line.split('=', 1)
                    val = val.strip().strip('\"')
                    key_part = key_part.strip()
                    
                    # Match Type(1), InitLat(1), Leg(1,0), etc.
                    match = re.match(r'([A-Za-z]+)\((\d+)(?:,\s*(\d+))?\)', key_part)
                    if match:
                        param = match.group(1)
                        v_idx = int(match.group(2))
                        sub_idx = match.group(3) # For Leg(N, M)
                        
                        if v_idx not in vessels:
                            vessels[v_idx] = {'index': v_idx, 'legs': []}
                        
                        if param == 'Leg':
                            # Store leg details
                            vessels[v_idx]['legs'].append(val)
                        elif param == 'Type':
                            vessels[v_idx]['type'] = val
                        elif param == 'InitLat':
                            vessels[v_idx]['lat'] = val
                        elif param == 'InitLong':
                            vessels[v_idx]['long'] = val
                        elif param == 'Speed':
                            vessels[v_idx]['speed'] = val
                        elif param == 'Bearing':
                            vessels[v_idx]['bearing'] = val
            
            # Convert dict to list
            result['scenario_data']['othership']['vessels'] = list(vessels.values())
            
        except Exception as e:
            result['files']['othership.ini']['error'] = str(e)
    else:
        result['files']['othership.ini'] = {'exists': False}

# 2. Check Radar Config (bc5.ini)
# Check multiple locations as BC uses user dir and install dir
config_files = [
    '/home/ga/.config/Bridge Command/bc5.ini',
    '/opt/bridgecommand/bc5.ini',
    '/home/ga/.Bridge Command/5.10/bc5.ini'
]
found_config = False
for cfg in config_files:
    if os.path.exists(cfg):
        try:
            with open(cfg, 'r', errors='ignore') as f:
                for line in f:
                    if '=' in line:
                        k, v = line.split('=', 1)
                        k = k.strip()
                        v = v.strip().strip('\"')
                        if k in ['arpa_on', 'full_radar', 'radar_range_resolution', 'max_radar_range', 'radar_angular_resolution']:
                            # Only overwrite if not set or if this file is newer (simple logic: last read wins)
                            result['radar_config'][k] = v
            found_config = True
        except:
            pass

# 3. Check Briefing Document
if os.path.exists(briefing_file):
    result['briefing']['exists'] = True
    result['briefing']['mtime'] = os.path.getmtime(briefing_file)
    try:
        with open(briefing_file, 'r', errors='ignore') as f:
            result['briefing']['content'] = f.read()[:5000] # Limit size
    except Exception as e:
        result['briefing']['error'] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="