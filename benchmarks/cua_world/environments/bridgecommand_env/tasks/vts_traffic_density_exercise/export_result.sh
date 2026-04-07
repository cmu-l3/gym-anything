#!/bin/bash
echo "=== Exporting VTS Traffic Density Exercise Results ==="

# Define paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/n) Solent VTS Traffic Density"
LOG_FILE="/home/ga/Documents/vts_watch_handover_log.txt"
TASK_START_FILE="/tmp/task_start_time.txt"

# 1. Capture Final Screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamps
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "pre_existing"
        fi
    else
        echo "false"
    fi
}

ENV_EXISTS=$(check_file "$SCENARIO_DIR/environment.ini")
OWN_EXISTS=$(check_file "$SCENARIO_DIR/ownship.ini")
OTHER_EXISTS=$(check_file "$SCENARIO_DIR/othership.ini")
LOG_EXISTS=$(check_file "$LOG_FILE")

# 3. Read File Contents using Python for robust INI parsing
# We use Python to parse the somewhat non-standard Bridge Command INI format
# (especially othership.ini with indexed keys like Type(1)=...)

python3 << EOF
import json
import os
import re
import sys

result = {
    "files": {
        "environment_ini": "$ENV_EXISTS",
        "ownship_ini": "$OWN_EXISTS",
        "othership_ini": "$OTHER_EXISTS",
        "log_file": "$LOG_EXISTS"
    },
    "environment": {},
    "ownship": {},
    "otherships": [],
    "log_content": "",
    "timestamp": "$(date -Iseconds)"
}

scenario_dir = "$SCENARIO_DIR"
log_file = "$LOG_FILE"

def parse_ini(filepath):
    data = {}
    if not os.path.exists(filepath):
        return data
    try:
        with open(filepath, 'r', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('//') or line.startswith('#'):
                    continue
                if '=' in line:
                    parts = line.split('=', 1)
                    key = parts[0].strip()
                    val = parts[1].strip().strip('"')
                    data[key] = val
    except Exception as e:
        print(f"Error reading {filepath}: {e}", file=sys.stderr)
    return data

def parse_othership(filepath):
    vessels = {}
    if not os.path.exists(filepath):
        return []
    
    try:
        with open(filepath, 'r', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if '=' not in line: continue
                
                parts = line.split('=', 1)
                key_raw = parts[0].strip()
                val = parts[1].strip().strip('"')
                
                # Regex to match Key(Index) or Key(Index,Leg)
                # We mainly care about top-level vessel properties: Type(1), InitLat(1), etc.
                match = re.match(r'(\w+)\((\d+)(?:,\d+)?\)', key_raw)
                
                if match:
                    prop = match.group(1)
                    idx = int(match.group(2))
                    
                    if idx not in vessels:
                        vessels[idx] = {"index": idx}
                    
                    # Store legs count specifically if key is 'Legs'
                    if prop == 'Legs':
                        vessels[idx]['legs_count'] = val
                    
                    # Store legs details if it's a leg property
                    if ',' in key_raw: 
                        # It's a leg property like Speed(1,1)
                        pass 
                    else:
                        vessels[idx][prop.lower()] = val
                        
        return list(vessels.values())
    except Exception as e:
        print(f"Error reading {filepath}: {e}", file=sys.stderr)
        return []

# Parse Environment
result['environment'] = parse_ini(os.path.join(scenario_dir, 'environment.ini'))

# Parse Ownship
result['ownship'] = parse_ini(os.path.join(scenario_dir, 'ownship.ini'))

# Parse Otherships
result['otherships'] = parse_othership(os.path.join(scenario_dir, 'othership.ini'))

# Read Log Content
if os.path.exists(log_file):
    try:
        with open(log_file, 'r', errors='ignore') as f:
            result['log_content'] = f.read()
    except:
        pass

# Save to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Parsed data saved to /tmp/task_result.json")
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="