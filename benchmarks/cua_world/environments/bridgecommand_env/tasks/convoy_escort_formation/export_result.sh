#!/bin/bash
echo "=== Exporting Convoy Escort Formation Results ==="

# Define paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/n) Channel Convoy Escort"
BC_CONFIG_FILE="/home/ga/.config/Bridge Command/bc5.ini"
BRIEF_FILE="/home/ga/Documents/convoy_escort_brief.txt"
EXPORT_FILE="/tmp/task_result.json"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python Script to Parse INI Files and Geometry
# We use python to robustly parse the INI files and output JSON
cat > /tmp/parser.py << 'EOF'
import configparser
import json
import os
import math
import glob
import re

result = {
    "scenario_found": False,
    "files_present": [],
    "environment": {},
    "ownship": {},
    "otherships": [],
    "config": {},
    "briefing": {"exists": False, "content_length": 0, "keywords": []}
}

scenario_dir = "/opt/bridgecommand/Scenarios/n) Channel Convoy Escort"
config_file = "/home/ga/.config/Bridge Command/bc5.ini"
brief_file = "/home/ga/Documents/convoy_escort_brief.txt"

# --- Parse Scenario Files ---
if os.path.exists(scenario_dir):
    result["scenario_found"] = True
    
    # Check for files
    for f in ["environment.ini", "ownship.ini", "othership.ini"]:
        if os.path.exists(os.path.join(scenario_dir, f)):
            result["files_present"].append(f)

    # Parse Environment
    env_path = os.path.join(scenario_dir, "environment.ini")
    if os.path.exists(env_path):
        try:
            with open(env_path, 'r') as f:
                content = f.read()
            # Ini parser requires section headers, so we add a dummy one
            parser = configparser.ConfigParser()
            parser.read_string("[DUMMY]\n" + content)
            result["environment"] = dict(parser["DUMMY"])
        except Exception as e:
            result["environment_error"] = str(e)

    # Parse Ownship
    own_path = os.path.join(scenario_dir, "ownship.ini")
    if os.path.exists(own_path):
        try:
            with open(own_path, 'r') as f:
                content = f.read()
            parser = configparser.ConfigParser()
            parser.read_string("[DUMMY]\n" + content)
            result["ownship"] = dict(parser["DUMMY"])
        except Exception as e:
            result["ownship_error"] = str(e)

    # Parse Othership (Indexed format needs special handling)
    other_path = os.path.join(scenario_dir, "othership.ini")
    if os.path.exists(other_path):
        try:
            ships = {}
            with open(other_path, 'r') as f:
                lines = f.readlines()
            
            for line in lines:
                line = line.strip()
                if "=" in line:
                    key, val = line.split("=", 1)
                    key = key.strip()
                    val = val.strip().strip('"')
                    
                    # Regex to extract index from Key(N)
                    match = re.match(r"(\w+)\((\d+)\)", key)
                    if match:
                        param = match.group(1)
                        idx = int(match.group(2))
                        if idx not in ships:
                            ships[idx] = {}
                        ships[idx][param] = val
                    elif key == "Number":
                        result["othership_count_declared"] = val

            result["otherships"] = [ships[i] for i in sorted(ships.keys())]
        except Exception as e:
            result["othership_error"] = str(e)

# --- Parse Config ---
if os.path.exists(config_file):
    try:
        with open(config_file, 'r') as f:
            content = f.read()
        # BC config often doesn't have sections, or uses weird ones. 
        # We'll just look for lines.
        cfg = {}
        for line in content.splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip().strip('"')
        result["config"] = cfg
    except Exception as e:
        result["config_error"] = str(e)

# --- Parse Briefing ---
if os.path.exists(brief_file):
    result["briefing"]["exists"] = True
    try:
        with open(brief_file, 'r', errors='ignore') as f:
            content = f.read().lower()
            result["briefing"]["content_length"] = len(content)
            keywords = ["formation", "bearing", "distance", "vhf", "threat", "course", "screen", "convoy"]
            found = [k for k in keywords if k in content]
            result["briefing"]["keywords"] = found
    except:
        pass

print(json.dumps(result, indent=2))
EOF

# Run parser and save output
python3 /tmp/parser.py > "$EXPORT_FILE"

# Make readable
chmod 666 "$EXPORT_FILE"

echo "Result exported to $EXPORT_FILE"