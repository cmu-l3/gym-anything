#!/bin/bash
echo "=== Exporting narrow_channel_rule9_exercise result ==="

# Paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/p) Southampton Water Rule 9 Exercise"
BRIEFING_FILE="/home/ga/Documents/rule9_channel_briefing.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to read file content if it exists
read_file_content() {
    if [ -f "$1" ]; then
        cat "$1" | base64 -w 0
    else
        echo ""
    fi
}

# Python script to parse INI files and generate JSON result
# We run this inside the container to package everything nicely
python3 -c "
import sys
import os
import configparser
import json
import time
import glob

def parse_ini_file(path):
    if not os.path.exists(path):
        return None
    
    # Bridge Command INI files are often just key=value lines without headers
    # or with mixed headers. We'll try to parse them manually to be robust.
    data = {}
    try:
        with open(path, 'r', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith(';'): continue
                if '=' in line:
                    key, val = line.split('=', 1)
                    key = key.strip()
                    val = val.strip().strip('\"')
                    data[key] = val
    except Exception as e:
        return {'error': str(e)}
    return data

def parse_othership(path):
    if not os.path.exists(path):
        return None
    
    # specialized parser for othership.ini which uses index keys like Type(1)=...
    vessels = {}
    try:
        with open(path, 'r', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if not line: continue
                
                if '=' in line:
                    key, val = line.split('=', 1)
                    key = key.strip()
                    val = val.strip().strip('\"')
                    
                    if '(' in key and ')' in key:
                        param_name = key.split('(')[0]
                        idx = key.split('(')[1].split(')')[0]
                        
                        if idx not in vessels:
                            vessels[idx] = {}
                        
                        if param_name == 'Leg':
                            # Handle legs special case if needed, or just store list
                            if 'legs' not in vessels[idx]: vessels[idx]['legs'] = []
                            vessels[idx]['legs'].append(val)
                        else:
                            vessels[idx][param_name] = val
                    elif key == 'Number':
                         vessels['meta_count'] = val
    except Exception as e:
        return {'error': str(e)}
    return vessels

def get_file_stats(path):
    if not os.path.exists(path):
        return {'exists': False}
    stats = os.stat(path)
    return {
        'exists': True,
        'size': stats.st_size,
        'mtime': stats.st_mtime,
        'created_after_start': stats.st_mtime > $TASK_START
    }

# 1. Analyze Scenario Directory
scenario_dir = '$SCENARIO_DIR'
result = {
    'timestamp': time.time(),
    'scenario_dir_exists': os.path.isdir(scenario_dir),
    'files': {}
}

# 2. Parse INI files
env_path = os.path.join(scenario_dir, 'environment.ini')
own_path = os.path.join(scenario_dir, 'ownship.ini')
other_path = os.path.join(scenario_dir, 'othership.ini')

result['environment'] = parse_ini_file(env_path)
result['ownship'] = parse_ini_file(own_path)
result['othership'] = parse_othership(other_path)
result['files']['environment.ini'] = get_file_stats(env_path)
result['files']['ownship.ini'] = get_file_stats(own_path)
result['files']['othership.ini'] = get_file_stats(other_path)

# 3. Analyze Briefing Document
briefing_path = '$BRIEFING_FILE'
result['briefing'] = get_file_stats(briefing_path)
if result['briefing']['exists']:
    try:
        with open(briefing_path, 'r', errors='ignore') as f:
            content = f.read()
            result['briefing']['word_count'] = len(content.split())
            result['briefing']['content_snippet'] = content[:1000] # Setup for verifier check
            # Simple keyword check in python to save verifier work
            keywords = ['Rule 9', 'Rule 34', 'Rule 6', 'starboard', 'overtaking']
            found_keys = [k for k in keywords if k.lower() in content.lower()]
            result['briefing']['keywords_found'] = found_keys
            result['briefing']['question_mark_count'] = content.count('?')
    except:
        result['briefing']['error'] = 'read_failed'

# 4. Check bc5.ini config
# Check multiple locations
config_locs = [
    '/home/ga/.config/Bridge Command/bc5.ini',
    '/opt/bridgecommand/bc5.ini',
    '/home/ga/.Bridge Command/5.10/bc5.ini'
]

bc5_config = {}
for loc in config_locs:
    if os.path.exists(loc):
        parsed = parse_ini_file(loc)
        if parsed:
            # Merge, preferring user config
            bc5_config.update(parsed)

result['bc5_config'] = bc5_config

# Write result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print('JSON result generated')
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="