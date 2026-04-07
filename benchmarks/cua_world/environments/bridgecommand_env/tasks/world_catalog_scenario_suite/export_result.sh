#!/bin/bash
echo "=== Exporting World Catalog Task Results ==="

# Paths
DOCS_DIR="/home/ga/Documents"
SCENARIO_ROOT="/opt/bridgecommand/Scenarios"
BC_CONFIG_USER="/home/ga/.config/Bridge Command/bc5.ini"
BC_CONFIG_SYSTEM="/opt/bridgecommand/bc5.ini"

# Output JSON path
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to parse INI files and gather all data
python3 -c "
import json
import os
import glob
import re
import time

def parse_ini(filepath):
    data = {}
    if not os.path.exists(filepath):
        return None
    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if '=' in line and not line.startswith(';'):
                    key, val = line.split('=', 1)
                    key = key.strip()
                    val = val.strip().strip('\"')
                    # Handle indexed keys like Type(1)
                    if '(' in key and ')' in key:
                        base_key = key.split('(')[0]
                        index = key.split('(')[1].split(')')[0]
                        if base_key not in data:
                            data[base_key] = {}
                        if isinstance(data[base_key], dict):
                            data[base_key][index] = val
                    else:
                        data[key] = val
    except Exception as e:
        data['_error'] = str(e)
    return data

def read_file(filepath, max_chars=2000):
    if not os.path.exists(filepath):
        return None
    try:
        with open(filepath, 'r') as f:
            return f.read()[:max_chars]
    except:
        return None

def get_file_mtime(filepath):
    if os.path.exists(filepath):
        return os.path.getmtime(filepath)
    return 0

# 1. Gather Documents
docs = {
    'world_catalog': {
        'exists': os.path.exists('$DOCS_DIR/world_catalog.txt'),
        'content': read_file('$DOCS_DIR/world_catalog.txt'),
        'mtime': get_file_mtime('$DOCS_DIR/world_catalog.txt')
    },
    'curriculum': {
        'exists': os.path.exists('$DOCS_DIR/curriculum_mapping.txt'),
        'content': read_file('$DOCS_DIR/curriculum_mapping.txt'),
        'mtime': get_file_mtime('$DOCS_DIR/curriculum_mapping.txt')
    }
}

# 2. Gather Scenarios
scenarios = {}
targets = {
    's1': 'x1) Open Water Exercise',
    's2': 'x2) Coastal Pilotage Exercise',
    's3': 'x3) Restricted Visibility Exercise'
}

for key, folder_name in targets.items():
    path = os.path.join('$SCENARIO_ROOT', folder_name)
    scenarios[key] = {
        'exists': os.path.isdir(path),
        'environment': parse_ini(os.path.join(path, 'environment.ini')),
        'ownship': parse_ini(os.path.join(path, 'ownship.ini')),
        'othership': parse_ini(os.path.join(path, 'othership.ini')),
        'mtime': get_file_mtime(os.path.join(path, 'environment.ini')) # approximate creation time
    }

# 3. Gather Config (Check both locations)
config_user = parse_ini('$BC_CONFIG_USER') or {}
config_system = parse_ini('$BC_CONFIG_SYSTEM') or {}
# Merge, user takes precedence
config = {**config_system, **config_user}

# 4. Get available worlds list
available_worlds = []
if os.path.exists('/tmp/available_worlds_list.txt'):
    with open('/tmp/available_worlds_list.txt', 'r') as f:
        available_worlds = [l.strip() for l in f if l.strip()]

# 5. Task timing
task_start = 0
if os.path.exists('/tmp/task_start_time.txt'):
    with open('/tmp/task_start_time.txt', 'r') as f:
        try:
            task_start = float(f.read().strip())
        except:
            pass

result = {
    'documents': docs,
    'scenarios': scenarios,
    'config': config,
    'available_worlds': available_worlds,
    'task_start': task_start,
    'timestamp': time.time()
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Result JSON generated at $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="