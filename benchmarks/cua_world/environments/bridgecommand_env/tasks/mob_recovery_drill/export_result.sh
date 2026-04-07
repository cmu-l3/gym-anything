#!/bin/bash
echo "=== Exporting MOB Recovery Drill Results ==="

# Define paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/o) MOB Recovery Drill"
DOC_PATH="/home/ga/Documents/mob_drill_procedures.txt"
BC_USER_CONFIG="/home/ga/.config/Bridge Command/bc5.ini"
BC_SYSTEM_CONFIG="/opt/bridgecommand/bc5.ini"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python Script to Parse INI Files and Document
# This runs INSIDE the container to safely extract complex data structures
cat > /tmp/parse_mob_task.py << 'PYEOF'
import configparser
import json
import os
import glob
import math

result = {
    "scenario_exists": False,
    "files_created_during_task": False,
    "environment": {},
    "ownship": {},
    "otherships": [],
    "config": {},
    "document": {"exists": False, "content": "", "keywords_found": []}
}

scenario_dir = "/opt/bridgecommand/Scenarios/o) MOB Recovery Drill"
start_time = int(os.environ.get("TASK_START_TIME", 0))

# --- Helper: Parse fake-INI format of Bridge Command ---
# BC files are often key=value without section headers, or use Key(N)=Value
def parse_bc_ini(filepath):
    data = {}
    if not os.path.exists(filepath):
        return data
        
    # Check timestamp
    if os.path.getmtime(filepath) > start_time:
        result["files_created_during_task"] = True
        
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('//') or line.startswith('#'):
                continue
            if '=' in line:
                key, val = line.split('=', 1)
                key = key.strip()
                val = val.strip().strip('"')
                data[key] = val
    return data

# --- 1. Parse Environment ---
if os.path.isdir(scenario_dir):
    result["scenario_exists"] = True
    env = parse_bc_ini(os.path.join(scenario_dir, "environment.ini"))
    result["environment"] = env

    # --- 2. Parse Ownship ---
    own = parse_bc_ini(os.path.join(scenario_dir, "ownship.ini"))
    result["ownship"] = own

    # --- 3. Parse Othership (Complex indexed format) ---
    other_raw = parse_bc_ini(os.path.join(scenario_dir, "othership.ini"))
    
    # Convert flat indexed keys Key(N) to list of objects
    ships = {}
    for key, val in other_raw.items():
        if '(' in key and ')' in key:
            param_name = key.split('(')[0]
            index = int(key.split('(')[1].split(')')[0])
            
            if index not in ships:
                ships[index] = {}
            ships[index][param_name] = val
        elif key == "Number":
            result["othership_count_param"] = val

    # Convert dict to sorted list
    result["otherships"] = [ships[i] for i in sorted(ships.keys())]

# --- 4. Parse Config (bc5.ini) ---
# Check both user and system config, preferring user
cfg_path = "/home/ga/.config/Bridge Command/bc5.ini"
if not os.path.exists(cfg_path):
    cfg_path = "/opt/bridgecommand/bc5.ini"
    
result["config"] = parse_bc_ini(cfg_path)

# --- 5. Parse Document ---
doc_path = "/home/ga/Documents/mob_drill_procedures.txt"
if os.path.exists(doc_path):
    result["document"]["exists"] = True
    if os.path.getmtime(doc_path) > start_time:
        result["document"]["created_during_task"] = True
    
    try:
        with open(doc_path, 'r', errors='ignore') as f:
            content = f.read()
            result["document"]["content"] = content
    except Exception as e:
        result["document"]["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Run the python script and save output
export TASK_START_TIME="$TASK_START_TIME"
python3 /tmp/parse_mob_task.py > /tmp/task_result.json 2>/dev/null || echo '{"error": "Parser failed"}' > /tmp/task_result.json

# Cleanup
rm -f /tmp/parse_mob_task.py

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export completed. JSON result generated."
cat /tmp/task_result.json