#!/bin/bash
echo "=== Exporting Radar Plotting Exercise Results ==="

# Define paths
BC_DATA="/opt/bridgecommand"
SCENARIO_NAME="o) Solent Radar Plotting Exercise"
SCENARIO_DIR="$BC_DATA/Scenarios/$SCENARIO_NAME"
SOLUTION_FILE="/home/ga/Documents/radar_plotting_solutions.txt"
CONFIG_FILE="/home/ga/.config/Bridge Command/bc5.ini"

# Record Task End
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- Data Extraction Helper ---
# Python script to parse INI files accurately (bash parsing is fragile for indexed keys)
cat > /tmp/parse_scenario.py << 'PYEOF'
import configparser
import json
import os
import sys
import re

def parse_ini_safely(filepath):
    """Parses INI file allowing for loose syntax (no headers sometimes)"""
    if not os.path.exists(filepath):
        return {}
    
    with open(filepath, 'r') as f:
        content = f.read()
    
    # Bridge Command INI files often lack section headers or use specific formats
    # We'll treat them as a flat key-value store for simplicity, 
    # except for indexed keys like Type(1)=...
    
    data = {}
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith(';') or line.startswith('#') or line.startswith('['):
            continue
        
        if '=' in line:
            key, value = line.split('=', 1)
            key = key.strip()
            value = value.strip().strip('"') # Remove quotes if present
            data[key] = value
    return data

result = {
    "scenario_found": False,
    "files": {
        "environment": {},
        "ownship": {},
        "othership": {},
        "config": {}
    },
    "solution_content": ""
}

scenario_dir = sys.argv[1]
solution_file = sys.argv[2]
config_file = sys.argv[3]

if os.path.isdir(scenario_dir):
    result["scenario_found"] = True
    result["files"]["environment"] = parse_ini_safely(os.path.join(scenario_dir, "environment.ini"))
    result["files"]["ownship"] = parse_ini_safely(os.path.join(scenario_dir, "ownship.ini"))
    result["files"]["othership"] = parse_ini_safely(os.path.join(scenario_dir, "othership.ini"))

# Parse Config (bc5.ini)
# BC5.ini usually has sections, so use ConfigParser but fallback to manual if fails
try:
    config = configparser.ConfigParser()
    config.read(config_file)
    for section in config.sections():
        for key, val in config.items(section):
            result["files"]["config"][key] = val
except:
    result["files"]["config"] = parse_ini_safely(config_file)

# Read Solution File
if os.path.exists(solution_file):
    with open(solution_file, 'r', errors='ignore') as f:
        result["solution_content"] = f.read()

print(json.dumps(result, indent=2))
PYEOF

# Run parser
python3 /tmp/parse_scenario.py "$SCENARIO_DIR" "$SOLUTION_FILE" "$CONFIG_FILE" > /tmp/parsed_data.json

# Combine with metadata
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "parsed_data": $(cat /tmp/parsed_data.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="