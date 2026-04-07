#!/bin/bash
echo "=== Exporting Oil Spill Boom Deployment Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/q) Oil Recovery V-Sweep"
DOC_FILE="/home/ga/Documents/boom_deployment_plan.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract Scenario Data using Python for robust INI parsing
# Bridge Command uses indexed keys like Key(1), Lat(1), which are hard to parse with bash.
python3 -c "
import os
import re
import json
import configparser

scenario_dir = '$SCENARIO_DIR'
doc_file = '$DOC_FILE'
task_start = int('$TASK_START')

result = {
    'scenario_exists': False,
    'files_created_during_task': False,
    'environment': {},
    'objects': [],
    'doc_content': '',
    'doc_exists': False
}

# Check directory
if os.path.isdir(scenario_dir):
    result['scenario_exists'] = True
    
    # Check modification time of the directory or key files
    try:
        mtime = os.path.getmtime(os.path.join(scenario_dir, 'othership.ini'))
        if mtime > task_start:
            result['files_created_during_task'] = True
    except:
        pass

    # Parse environment.ini (Simple key=value)
    env_path = os.path.join(scenario_dir, 'environment.ini')
    if os.path.exists(env_path):
        with open(env_path, 'r', errors='ignore') as f:
            for line in f:
                if '=' in line:
                    key, val = line.strip().split('=', 1)
                    result['environment'][key.strip()] = val.strip()

    # Parse othership.ini (Indexed format: Key(N)=Value)
    other_path = os.path.join(scenario_dir, 'othership.ini')
    if os.path.exists(other_path):
        objects = {} # Temp dict to group by index
        with open(other_path, 'r', errors='ignore') as f:
            for line in f:
                line = line.strip()
                # Match pattern like Key(1)=Value
                match = re.match(r'([A-Za-z]+)\((\d+)\)=(.*)', line)
                if match:
                    param, index, value = match.groups()
                    index = int(index)
                    if index not in objects:
                        objects[index] = {}
                    objects[index][param.lower()] = value
        
        # Convert to list
        result['objects'] = list(objects.values())

# Parse Documentation
if os.path.exists(doc_file):
    result['doc_exists'] = True
    try:
        with open(doc_file, 'r', errors='ignore') as f:
            result['doc_content'] = f.read()
    except:
        pass

# Output JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 3. Secure output file
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete. JSON content:"
cat /tmp/task_result.json