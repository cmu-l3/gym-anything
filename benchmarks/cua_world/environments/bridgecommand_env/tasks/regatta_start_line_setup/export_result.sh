#!/bin/bash
echo "=== Exporting Regatta Start Line Result ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/r) Cowes Regatta Start"
DOCS_FILE="/home/ga/Documents/sailing_instructions.txt"

# 1. Take final screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || true

# 2. Check file existence/timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SCENARIO_CREATED="false"
FILES_NEW="false"

if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_CREATED="true"
    # Check if environment.ini is newer than task start
    ENV_TIME=$(stat -c %Y "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "0")
    if [ "$ENV_TIME" -gt "$TASK_START" ]; then
        FILES_NEW="true"
    fi
fi

# 3. Extract Scenario Data using Python for reliability
# We parse the INI files directly into a JSON structure
python3 << EOF
import configparser
import json
import os
import sys

result = {
    "scenario_exists": False,
    "files_created_during_task": $FILES_NEW,
    "environment": {},
    "ownship": {},
    "othership": [],
    "docs_exists": False,
    "docs_content": ""
}

scenario_dir = "$SCENARIO_DIR"

if os.path.exists(scenario_dir):
    result["scenario_exists"] = True
    
    # Parse environment.ini (Key=Value format)
    env_path = os.path.join(scenario_dir, "environment.ini")
    if os.path.exists(env_path):
        try:
            with open(env_path, 'r') as f:
                for line in f:
                    if '=' in line:
                        k, v = line.strip().split('=', 1)
                        result["environment"][k.strip()] = v.strip()
        except Exception as e:
            result["env_error"] = str(e)

    # Parse ownship.ini (Key=Value format)
    own_path = os.path.join(scenario_dir, "ownship.ini")
    if os.path.exists(own_path):
        try:
            with open(own_path, 'r') as f:
                for line in f:
                    if '=' in line:
                        k, v = line.strip().split('=', 1)
                        result["ownship"][k.strip()] = v.strip()
        except Exception as e:
            result["own_error"] = str(e)

    # Parse othership.ini (Indexed Key(N)=Value format)
    # Bridge Command othership.ini is weird: Type(1)=ferry
    other_path = os.path.join(scenario_dir, "othership.ini")
    if os.path.exists(other_path):
        try:
            vessels = {}
            with open(other_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if '=' in line and '(' in line and ')' in line:
                        key_part, val = line.split('=', 1)
                        param_name = key_part.split('(')[0].strip()
                        index = key_part.split('(')[1].split(')')[0].strip()
                        
                        if index not in vessels:
                            vessels[index] = {}
                        
                        vessels[index][param_name] = val.strip().strip('"')
            
            # Convert dict to list
            result["othership"] = [vessels[k] for k in sorted(vessels.keys(), key=lambda x: int(x) if x.isdigit() else x)]
            
        except Exception as e:
            result["other_error"] = str(e)

# Check documentation
docs_path = "$DOCS_FILE"
if os.path.exists(docs_path):
    result["docs_exists"] = True
    try:
        with open(docs_path, 'r') as f:
            result["docs_content"] = f.read(500)
    except:
        pass

# Save to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
EOF

# 4. Handle permissions so verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="