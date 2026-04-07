#!/bin/bash
echo "=== Exporting create_dotprobe_bias_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess
import csv

EXP_FILE = "/home/ga/PsychoPyExperiments/dot_probe_bias.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/conditions/dot_probe_conditions.csv"
RESULT_FILE = "/tmp/create_dotprobe_bias_task_result.json"

results = {
    "exp_exists": False,
    "exp_modified": False,
    "cond_exists": False,
    "cond_modified": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    "psychopy_running": False,
    # CSV Analysis
    "csv_rows": 0,
    "csv_columns": [],
    "csv_threat_words": [],
    "csv_congruent_count": 0,
    "csv_incongruent_count": 0,
    "csv_valid_corrans": True,
    # PsyExp Analysis
    "exp_routines": [],
    "exp_has_loop": False,
    "exp_loop_file": "",
    "exp_components": [],
}

# Read task start time
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass

# Read nonce
try:
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

# Check PsychoPy process
try:
    ps = subprocess.run(["pgrep", "-f", "psychopy"], capture_output=True)
    results["psychopy_running"] = ps.returncode == 0
except:
    pass

# Check Files
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    if int(os.path.getmtime(EXP_FILE)) > results["task_start_time"]:
        results["exp_modified"] = True

if os.path.isfile(COND_FILE):
    results["cond_exists"] = True
    if int(os.path.getmtime(COND_FILE)) > results["task_start_time"]:
        results["cond_modified"] = True

# Analyze CSV content
if results["cond_exists"]:
    try:
        with open(COND_FILE, 'r', newline='') as f:
            reader = csv.DictReader(f)
            results["csv_columns"] = reader.fieldnames if reader.fieldnames else []
            rows = list(reader)
            results["csv_rows"] = len(rows)
            
            for row in rows:
                if "threatWord" in row:
                    results["csv_threat_words"].append(row["threatWord"].lower())
                
                cong = row.get("congruency", "").lower()
                if "incongruent" in cong:
                    results["csv_incongruent_count"] += 1
                elif "congruent" in cong:
                    results["csv_congruent_count"] += 1
                    
                # Validate answer mapping logic (probePos vs corrAns)
                ppos = row.get("probePos", "").lower()
                ans = row.get("corrAns", "").lower()
                if ppos == "top" and ans != "up":
                    results["csv_valid_corrans"] = False
                if ppos == "bottom" and ans != "down":
                    results["csv_valid_corrans"] = False

    except Exception as e:
        print(f"CSV Parse Error: {e}", file=sys.stderr)

# Analyze PsyExp content (XML)
if results["exp_exists"]:
    try:
        import xml.etree.ElementTree as ET
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        
        # Get routines
        for routine in root.findall(".//Routine"):
            rname = routine.get("name")
            results["exp_routines"].append(rname)
            
            # Get components in routine
            for comp in routine:
                cname = comp.get("name")
                ctype = comp.tag
                results["exp_components"].append({"name": cname, "type": ctype, "routine": rname})

        # Get Loop info
        for loop in root.findall(".//LoopInitiator"):
            results["exp_has_loop"] = True
            for param in loop:
                if param.get("name") == "conditionsFile":
                    results["exp_loop_file"] = param.get("val")

    except Exception as e:
        print(f"XML Parse Error: {e}", file=sys.stderr)

# Save result
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)
os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_dotprobe_bias_task_result.json
echo "=== Export complete ==="