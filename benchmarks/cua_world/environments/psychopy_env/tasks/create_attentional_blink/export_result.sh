#!/bin/bash
echo "=== Exporting Attentional Blink task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
EXP_FILE="/home/ga/PsychoPyExperiments/attentional_blink.psyexp"
COND_FILE="/home/ga/PsychoPyExperiments/conditions/ab_conditions.csv"
RESULT_JSON="/tmp/task_result.json"

# Python script to analyze the files and environment state
python3 << 'PYEOF'
import json
import os
import sys
import csv
import xml.etree.ElementTree as ET
import datetime

exp_path = "/home/ga/PsychoPyExperiments/attentional_blink.psyexp"
cond_path = "/home/ga/PsychoPyExperiments/conditions/ab_conditions.csv"
nonce_path = "/home/ga/.task_nonce"
start_time_path = "/home/ga/.task_start_time"

result = {
    "timestamp": datetime.datetime.now().isoformat(),
    "task_start_time": 0,
    "nonce": "",
    "exp_exists": False,
    "exp_modified": False,
    "cond_exists": False,
    "cond_modified": False,
    # XML Analysis
    "xml_valid": False,
    "routines": [],
    "components": [],
    "loops": [],
    "has_code_component": False,
    "has_keyboard": False,
    "has_text": False,
    # CSV Analysis
    "csv_valid": False,
    "csv_columns": [],
    "csv_row_count": 0,
    "unique_lags": [],
    "has_t2_column": False
}

# Load Metadata
try:
    with open(start_time_path, 'r') as f:
        result["task_start_time"] = int(f.read().strip())
except:
    pass

try:
    with open(nonce_path, 'r') as f:
        result["nonce"] = f.read().strip()
except:
    pass

# Check Experiment File
if os.path.exists(exp_path):
    result["exp_exists"] = True
    if os.path.getmtime(exp_path) > result["task_start_time"]:
        result["exp_modified"] = True
    
    try:
        tree = ET.parse(exp_path)
        root = tree.getroot()
        result["xml_valid"] = True
        
        # Extract Routines
        for routine in root.iter('Routine'):
            r_name = routine.get('name', 'unknown')
            result["routines"].append(r_name)
            
            # Extract Components in Routine
            for comp in routine:
                c_type = comp.tag
                c_name = comp.get('name', 'unknown')
                result["components"].append({"type": c_type, "name": c_name, "routine": r_name})
                
                if 'CodeComponent' in c_type or 'Code' in c_type:
                    result["has_code_component"] = True
                if 'Keyboard' in c_type:
                    result["has_keyboard"] = True
                if 'Text' in c_type:
                    result["has_text"] = True

        # Extract Loops
        for loop in root.iter('LoopInitiator'):
            # Check conditions file linkage
            params = loop.findall('Param')
            loop_info = {"name": loop.get('name', 'loop')}
            for p in params:
                if p.get('name') == 'conditionsFile':
                    loop_info['conditionsFile'] = p.get('val')
            result["loops"].append(loop_info)
            
    except Exception as e:
        result["xml_error"] = str(e)

# Check Conditions File
if os.path.exists(cond_path):
    result["cond_exists"] = True
    if os.path.getmtime(cond_path) > result["task_start_time"]:
        result["cond_modified"] = True
        
    try:
        with open(cond_path, 'r', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                result["csv_columns"] = [c.lower() for c in reader.fieldnames]
                
                # Check required columns
                if 'lag' in result["csv_columns"]:
                    lags = set()
                    rows = list(reader)
                    result["csv_row_count"] = len(rows)
                    for row in rows:
                        # Find lag column case-insensitively
                        for k, v in row.items():
                            if k.lower() == 'lag':
                                try:
                                    lags.add(int(v))
                                except:
                                    pass
                    result["unique_lags"] = list(lags)
                
                if any(x in result["csv_columns"] for x in ['t2_present', 't2present', 'target2_present']):
                    result["has_t2_column"] = True
            else:
                result["csv_valid"] = False # Empty file
            
            # Determine validity based on content read
            if reader.fieldnames:
                result["csv_valid"] = True
                
    except Exception as e:
        result["csv_error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="