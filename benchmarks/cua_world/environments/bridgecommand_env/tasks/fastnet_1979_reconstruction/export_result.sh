#!/bin/bash
echo "=== Exporting Fastnet '79 Reconstruction Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/z) Fastnet 1979 Reconstruction"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if directory exists
if [ -d "$SCENARIO_DIR" ]; then
    DIR_EXISTS="true"
else
    DIR_EXISTS="false"
fi

# We use Python to parse the INI files robustly and export a JSON
# This handles the Bridge Command specific INI format (flat keys in some, indexed keys in others)
python3 -c "
import os
import json
import configparser
import re

scenario_dir = '$SCENARIO_DIR'
result = {
    'dir_exists': False,
    'environment': {},
    'ownship': {},
    'otherships': [],
    'files_created_during_task': False
}

if os.path.exists(scenario_dir):
    result['dir_exists'] = True
    
    # Check timestamps
    try:
        mtime = os.path.getmtime(scenario_dir)
        task_start = float($TASK_START)
        if mtime > task_start:
            result['files_created_during_task'] = True
    except:
        pass

    # --- Parse environment.ini ---
    env_path = os.path.join(scenario_dir, 'environment.ini')
    if os.path.exists(env_path):
        # environment.ini is roughly key=value
        try:
            with open(env_path, 'r') as f:
                content = f.read()
                # Simple parsing for known keys
                for line in content.splitlines():
                    if '=' in line:
                        key, val = line.split('=', 1)
                        result['environment'][key.strip()] = val.strip().replace('\"', '')
        except Exception as e:
            print(f'Error parsing environment: {e}')

    # --- Parse ownship.ini ---
    own_path = os.path.join(scenario_dir, 'ownship.ini')
    if os.path.exists(own_path):
        try:
            with open(own_path, 'r') as f:
                content = f.read()
                for line in content.splitlines():
                    if '=' in line:
                        key, val = line.split('=', 1)
                        result['ownship'][key.strip()] = val.strip().replace('\"', '')
        except:
            pass

    # --- Parse othership.ini ---
    # This is trickier: Key(Index)=Value
    other_path = os.path.join(scenario_dir, 'othership.ini')
    if os.path.exists(other_path):
        try:
            vessels = {}
            with open(other_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    # Match pattern: Key(Index)=Value
                    m = re.match(r'([A-Za-z]+)\((\d+)\)=(.*)', line)
                    if m:
                        key = m.group(1)
                        idx = int(m.group(2))
                        val = m.group(3).strip().replace('\"', '')
                        
                        if idx not in vessels:
                            vessels[idx] = {}
                        vessels[idx][key] = val
            
            # Convert dict to list
            result['otherships'] = [vessels[i] for i in sorted(vessels.keys())]
        except Exception as e:
            print(f'Error parsing otherships: {e}')

# Output JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so the host can read it (if needed, though copy_from_env usually handles root)
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "Export completed. Result:"
cat /tmp/task_result.json