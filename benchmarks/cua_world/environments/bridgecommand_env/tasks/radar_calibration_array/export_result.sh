#!/bin/bash
echo "=== Exporting Radar Calibration Array Result ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/z) Radar Calibration"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot for visual evidence
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if scenario directory was created
if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
else
    SCENARIO_EXISTS="false"
fi

# Use Python to parse the INI files and export a clean JSON structure
# This avoids complex bash parsing and handles the INI structure robustly
python3 << PYEOF
import configparser
import json
import os
import glob
import re

result = {
    "scenario_exists": False,
    "files": {},
    "ownship": {},
    "otherships": [],
    "environment": {},
    "model_check": {},
    "timestamp": $TASK_END
}

scenario_dir = "$SCENARIO_DIR"
bc_models_dir = "$BC_DATA/Models"

if os.path.exists(scenario_dir):
    result["scenario_exists"] = True
    
    # Check required files
    for fname in ["environment.ini", "ownship.ini", "othership.ini"]:
        fpath = os.path.join(scenario_dir, fname)
        if os.path.exists(fpath):
            result["files"][fname] = True
            
            # Read file content for parsing
            try:
                with open(fpath, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    
                # Parse environment.ini
                if fname == "environment.ini":
                    # Simple key-value parsing
                    for line in content.splitlines():
                        if '=' in line:
                            key, val = line.split('=', 1)
                            result["environment"][key.strip().lower()] = val.strip().strip('"')
                            
                # Parse ownship.ini
                elif fname == "ownship.ini":
                    for line in content.splitlines():
                        if '=' in line:
                            key, val = line.split('=', 1)
                            result["ownship"][key.strip().lower()] = val.strip().strip('"')

                # Parse othership.ini
                elif fname == "othership.ini":
                    # This file uses indexed keys like Type(1)=...
                    # We will collect them into a dictionary keyed by index
                    ships = {}
                    for line in content.splitlines():
                        # Match pattern Key(Index)=Value
                        m = re.match(r'([a-zA-Z]+)\(([0-9]+)\)=(.*)', line.strip())
                        if m:
                            key = m.group(1).lower()
                            idx = int(m.group(2))
                            val = m.group(3).strip().strip('"')
                            
                            if idx not in ships:
                                ships[idx] = {}
                            ships[idx][key] = val
                    
                    # Convert to list
                    result["otherships"] = [ships[i] for i in sorted(ships.keys())]
                    
            except Exception as e:
                result["errors"] = str(e)
        else:
            result["files"][fname] = False

    # Check model existence (validation aid)
    # Collect all model names used
    used_models = set()
    if "type" in result.get("ownship", {}):
        used_models.add(result["ownship"]["type"])
    for ship in result.get("otherships", []):
        if "type" in ship:
            used_models.add(ship["type"])
            
    for model_name in used_models:
        # Check if directory exists in Models/Ownship or Models/Other or Models/
        found = False
        for subdir in ["", "Ownship", "Other"]:
            check_path = os.path.join(bc_models_dir, subdir, model_name)
            if os.path.exists(check_path):
                found = True
                break
        result["model_check"][model_name] = found

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="