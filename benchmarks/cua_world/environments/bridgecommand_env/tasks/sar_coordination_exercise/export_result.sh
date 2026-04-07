#!/bin/bash
echo "=== Exporting SAR Coordination Results ==="

# Define paths
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/s) Solent SAR Exercise"
SITREP_FILE="/home/ga/Documents/sar_sitrep.txt"
CONFIG_FILE="/home/ga/.config/Bridge Command/bc5.ini"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if scenario directory exists
if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
else
    SCENARIO_EXISTS="false"
fi

# Check if SITREP exists
if [ -f "$SITREP_FILE" ]; then
    SITREP_EXISTS="true"
    SITREP_CONTENT_PREVIEW=$(head -c 1000 "$SITREP_FILE" | base64 -w 0)
else
    SITREP_EXISTS="false"
    SITREP_CONTENT_PREVIEW=""
fi

# Use Python to robustly parse the INI files and calculate geometry
# We embed this python script to run inside the container environment
python3 -c "
import configparser
import json
import math
import os
import sys

def parse_bridge_command_ini(filepath):
    """
    Bridge Command INI files often duplicate keys or use indexed keys like Key(1)=Val.
    Standard configparser fails on duplicates and doesn't handle Index(N) naturally.
    We parse manually to dictionary of dictionaries/lists.
    """
    data = {}
    if not os.path.exists(filepath):
        return None
    
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()

    current_section = 'root'
    data[current_section] = {}

    for line in lines:
        line = line.strip()
        if not line or line.startswith(';'):
            continue
        
        if line.startswith('[') and line.endswith(']'):
            current_section = line[1:-1]
            if current_section not in data:
                data[current_section] = {}
            continue
        
        if '=' in line:
            key, val = line.split('=', 1)
            key = key.strip()
            val = val.strip().strip('\"') # Remove quotes if present
            
            # Handle indexed keys: Speed(1), Lat(1), Legs(1)
            if '(' in key and key.endswith(')'):
                base_key = key.split('(')[0]
                index_part = key.split('(')[1][:-1]
                
                # Handle 2D indices: Bearing(1,2)
                if ',' in index_part:
                    v_idx, leg_idx = index_part.split(',')
                    if base_key not in data[current_section]:
                        data[current_section][base_key] = {}
                    if v_idx not in data[current_section][base_key]:
                        data[current_section][base_key][v_idx] = {}
                    data[current_section][base_key][v_idx][leg_idx] = val
                else:
                    # 1D index: Type(1)
                    if base_key not in data[current_section]:
                        data[current_section][base_key] = {}
                    data[current_section][base_key][index_part] = val
            else:
                # Flat key
                data[current_section][key] = val

    return data

def analyze_geometry(vessels_data):
    """
    Analyze waypoints to detect expanding square patterns.
    Returns logic for each vessel index.
    """
    analysis = {}
    
    # Check if we have necessary data
    if not vessels_data or 'root' not in vessels_data:
        return {}
    
    root = vessels_data['root']
    
    # Get vessel count
    count = int(root.get('Number', 0))
    
    # Iterate through possible vessel indices
    # Bridge Command usually uses 1-based indexing for these files
    for i in range(1, count + 1):
        idx = str(i)
        vessel_info = {
            'name': root.get('Name', {}).get(idx, 'Unknown'), # Sometimes Name(1) exists
            'type': root.get('Type', {}).get(idx, 'Unknown'),
            'speed': float(root.get('InitialSpeed', {}).get(idx, 0.0)),
            'lat': float(root.get('InitialLat', {}).get(idx, 0.0)),
            'long': float(root.get('InitialLong', {}).get(idx, 0.0)),
            'legs_count': int(root.get('Legs', {}).get(idx, 0)),
            'is_square_pattern': False,
            'is_casualty': False
        }
        
        # Check if it's the casualty (speed 0)
        if vessel_info['speed'] < 0.1:
            vessel_info['is_casualty'] = True
            
        # Analyze legs for square pattern
        # Look for Bearing(idx, leg)
        bearings = []
        if 'Bearing' in root and idx in root['Bearing']:
            legs_dict = root['Bearing'][idx]
            # Sort by leg index
            sorted_legs = sorted([int(k) for k in legs_dict.keys()])
            for leg_idx in sorted_legs:
                bearings.append(float(legs_dict[str(leg_idx)]))
        
        # Expanding square logic: Bearings should change by approx 90 degrees (+/- 90) repeatedly
        turns_90 = 0
        if len(bearings) >= 3:
            for j in range(len(bearings) - 1):
                diff = abs(bearings[j+1] - bearings[j])
                # Normalize to 0-360
                while diff > 360: diff -= 360
                
                # Check for 90 deg turn (allow 70-110 or 250-290)
                if (70 <= diff <= 110) or (250 <= diff <= 290):
                    turns_90 += 1
            
            if turns_90 >= 3:
                vessel_info['is_square_pattern'] = True
        
        analysis[idx] = vessel_info
        
    return analysis

def parse_bc5_ini(filepath):
    if not os.path.exists(filepath):
        return {}
    config = configparser.ConfigParser()
    try:
        config.read(filepath)
        # Flatten for easier checking
        flat = {}
        for sec in config.sections():
            for k, v in config.items(sec):
                flat[k] = v
        return flat
    except:
        return {}

# --- Main Execution ---

result = {
    'scenario_dir_exists': '$SCENARIO_EXISTS' == 'true',
    'sitrep_exists': '$SITREP_EXISTS' == 'true',
    'sitrep_content_b64': '$SITREP_CONTENT_PREVIEW',
    'files': {
        'environment': False,
        'ownship': False,
        'othership': False
    },
    'env_data': {},
    'own_data': {},
    'other_data': {},
    'geometry': {},
    'config_data': {}
}

base_dir = '$SCENARIO_DIR'
env_path = os.path.join(base_dir, 'environment.ini')
own_path = os.path.join(base_dir, 'ownship.ini')
other_path = os.path.join(base_dir, 'othership.ini')
config_path = '$CONFIG_FILE'

# Parse Environment
if os.path.exists(env_path):
    result['files']['environment'] = True
    parsed = parse_bridge_command_ini(env_path)
    if parsed and 'root' in parsed:
        result['env_data'] = parsed['root']

# Parse Ownship
if os.path.exists(own_path):
    result['files']['ownship'] = True
    parsed = parse_bridge_command_ini(own_path)
    if parsed and 'root' in parsed:
        result['own_data'] = parsed['root']

# Parse Othership
if os.path.exists(other_path):
    result['files']['othership'] = True
    parsed = parse_bridge_command_ini(other_path)
    if parsed:
        result['geometry'] = analyze_geometry(parsed)
        # Store raw count
        if 'root' in parsed:
            result['other_data']['count'] = parsed['root'].get('Number', 0)

# Parse bc5.ini
if os.path.exists(config_path):
    result['config_data'] = parse_bc5_ini(config_path)

# Write result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="