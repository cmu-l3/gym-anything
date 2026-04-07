#!/bin/bash
echo "=== Exporting create_operation_span_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Use Python to analyze the experiment structure and CSV files
python3 << 'PYEOF'
import json
import os
import csv
import datetime
import subprocess
import xml.etree.ElementTree as ET

BASE_DIR = "/home/ga/PsychoPyExperiments/ospan"
EXP_FILE = os.path.join(BASE_DIR, "ospan.psyexp")
COND_DIR = os.path.join(BASE_DIR, "conditions")
RESULT_FILE = "/tmp/ospan_result.json"

results = {
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    "dir_exists": False,
    "exp_exists": False,
    "exp_valid_xml": False,
    "csv_files": {},
    "structure": {
        "routines": [],
        "loops": [],
        "flow_order": [],
        "nested_loops_detected": False,
        "dynamic_conditions_detected": False
    }
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

# Check directories and CSVs
if os.path.isdir(BASE_DIR):
    results["dir_exists"] = True
    
    # Check CSVs
    for fname in ["set_size_3.csv", "set_size_4.csv", "block_list.csv"]:
        fpath = os.path.join(COND_DIR, fname)
        file_info = {"exists": False, "rows": 0, "cols": []}
        if os.path.isfile(fpath):
            file_info["exists"] = True
            try:
                with open(fpath, 'r') as csvfile:
                    reader = csv.reader(csvfile)
                    rows = list(reader)
                    if rows:
                        file_info["cols"] = [c.strip() for c in rows[0]]
                        file_info["rows"] = len(rows) # including header
            except:
                pass
        results["csv_files"][fname] = file_info

# Analyze Experiment File
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["exp_valid_xml"] = True
            
        # Extract Routines
        for routine in root.findall(".//Routine"):
            results["structure"]["routines"].append(routine.get("name"))
            
        # Extract Flow
        flow = root.find(".//Flow")
        if flow is not None:
            loop_stack = []
            
            for child in flow:
                # Loop Initiator
                if child.tag == "LoopInitiator":
                    loop_name = child.get("name")
                    loop_node = child.find(f".//*[@name='{loop_name}']")
                    
                    # Check loop properties
                    conditions_file = ""
                    if loop_node is not None:
                        for param in loop_node:
                            if param.get("name") == "conditionsFile":
                                conditions_file = param.get("val")
                    
                    loop_info = {
                        "name": loop_name,
                        "type": "initiator",
                        "conditions_file": conditions_file,
                        "depth": len(loop_stack)
                    }
                    results["structure"]["flow_order"].append(loop_info)
                    loop_stack.append(loop_info)
                    results["structure"]["loops"].append(loop_info)

                # Loop Terminator
                elif child.tag == "LoopTerminator":
                    if loop_stack:
                        popped = loop_stack.pop()
                        results["structure"]["flow_order"].append({
                            "name": popped["name"],
                            "type": "terminator",
                            "depth": len(loop_stack)
                        })
                
                # Routine
                elif child.tag == "Routine":
                    results["structure"]["flow_order"].append({
                        "name": child.get("name"),
                        "type": "routine",
                        "depth": len(loop_stack)
                    })

            # Logic checks based on extracted flow
            # Check for nesting: A loop initiator followed by another initiator before a terminator
            flow = results["structure"]["flow_order"]
            for i in range(len(flow) - 1):
                if flow[i]["type"] == "initiator" and flow[i+1]["type"] == "initiator":
                    results["structure"]["nested_loops_detected"] = True
                    
                    # Check if the inner loop uses a variable for conditions
                    inner_loop_cond = flow[i+1]["conditions_file"]
                    if "$" in inner_loop_cond or "conditionFile" in inner_loop_cond:
                        results["structure"]["dynamic_conditions_detected"] = True
                    break

    except Exception as e:
        results["error"] = str(e)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
PYEOF

echo "Result exported to $RESULT_FILE"