#!/bin/bash
echo "=== Exporting Human Factors Experiment Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
MANIFEST_PATH="/home/ga/Documents/experiment_manifest.csv"
SCENARIO_ROOT="/opt/bridgecommand/Scenarios/z) Experiment_Batch_2026"

# Capture final state screenshot (file manager or terminal view ideally, but desktop is fine)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We use an embedded python script to parse the INI files and directory structure
# This is more robust than bash for handling INI parsing and logic
python3 -c "
import os
import csv
import json
import configparser
import time

result = {
    'task_start': $TASK_START,
    'scenarios': {},
    'manifest': {'exists': False, 'rows': []},
    'structure_correct': False
}

root_dir = '$SCENARIO_ROOT'
conditions = ['Cond_A_LoVis_LoTraf', 'Cond_B_LoVis_HiTraf', 'Cond_C_HiVis_LoTraf', 'Cond_D_HiVis_HiTraf']

# 1. Parse Scenarios
if os.path.exists(root_dir):
    result['structure_correct'] = True
    for cond in conditions:
        path = os.path.join(root_dir, cond)
        info = {'exists': False, 'vis': None, 'ship_count': None, 'env_valid': False, 'other_valid': False}
        
        if os.path.isdir(path):
            info['exists'] = True
            
            # Check modification time
            mtime = os.path.getmtime(path)
            info['modified_during_task'] = mtime > $TASK_START
            
            # Parse environment.ini
            env_path = os.path.join(path, 'environment.ini')
            if os.path.exists(env_path):
                try:
                    # Bridge command INIs are sometimes key=value without section headers
                    # We'll treat them as having a dummy section for configparser
                    with open(env_path, 'r') as f:
                        content = '[root]\n' + f.read()
                    cp = configparser.ConfigParser()
                    cp.read_string(content)
                    info['vis'] = cp.getfloat('root', 'VisibilityRange', fallback=None)
                    info['env_valid'] = True
                except Exception as e:
                    info['env_error'] = str(e)

            # Parse othership.ini
            other_path = os.path.join(path, 'othership.ini')
            if os.path.exists(other_path):
                try:
                    with open(other_path, 'r') as f:
                        content = '[root]\n' + f.read()
                    cp = configparser.ConfigParser()
                    cp.read_string(content)
                    info['ship_count'] = cp.getint('root', 'Number', fallback=None)
                    info['other_valid'] = True
                except Exception as e:
                    info['other_error'] = str(e)
        
        result['scenarios'][cond] = info
else:
    result['structure_correct'] = False

# 2. Parse Manifest
manifest_path = '$MANIFEST_PATH'
if os.path.exists(manifest_path):
    result['manifest']['exists'] = True
    result['manifest']['mtime'] = os.path.getmtime(manifest_path)
    try:
        with open(manifest_path, 'r') as f:
            reader = csv.DictReader(f)
            # Check headers
            if reader.fieldnames:
                result['manifest']['headers'] = reader.fieldnames
                for row in reader:
                    result['manifest']['rows'].append(row)
    except Exception as e:
        result['manifest']['error'] = str(e)

# Output JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Copy result to location accessible by verifier (with safe permissions)
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="