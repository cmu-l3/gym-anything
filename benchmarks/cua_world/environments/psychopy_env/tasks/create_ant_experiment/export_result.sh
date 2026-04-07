#!/bin/bash
echo "=== Exporting ANT Experiment Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Analyze experiment files and generate result JSON
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess
import csv

EXP_FILE = "/home/ga/PsychoPyExperiments/ant_experiment.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/ant_conditions.csv"
COND_FILE_ALT = "/home/ga/PsychoPyExperiments/conditions/ant_conditions.csv"
RESULT_FILE = "/tmp/create_ant_experiment_result.json"

results = {
    "exp_file_exists": False,
    "exp_file_modified": False,
    "exp_file_size": 0,
    "cond_file_exists": False,
    "cond_file_modified": False,
    "cond_file_size": 0,
    "cond_file_path": "",
    "psychopy_running": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    # CSV analysis
    "csv_columns": [],
    "csv_row_count": 0,
    "csv_cue_types": [],
    "csv_flanker_types": [],
    "csv_target_locations": [],
    "csv_target_directions": [],
    "csv_corrAns_values": [],
    "csv_corrAns_matches_direction": False,
    # psyexp analysis
    "is_valid_xml": False,
    "routine_names": [],
    "routine_count": 0,
    "loop_count": 0,
    "loop_conditions_files": [],
    "param_count": 0,
    "line_count": 0,
    "has_code_component": False,
    "code_content": "",
    "component_names": [],
    "component_types": [],
    "has_keyboard_component": False,
    "has_text_component": False,
    "keyboard_allowed_keys": [],
    "flow_element_count": 0
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

# Check PsychoPy running
try:
    ps = subprocess.run(["pgrep", "-f", "psychopy"], capture_output=True)
    results["psychopy_running"] = ps.returncode == 0
except:
    pass

# ---- Check Experiment File ----
if os.path.isfile(EXP_FILE):
    results["exp_file_exists"] = True
    results["exp_file_size"] = os.path.getsize(EXP_FILE)
    mtime = int(os.path.getmtime(EXP_FILE))
    if mtime > results["task_start_time"]:
        results["exp_file_modified"] = True

    # Parse XML
    try:
        import xml.etree.ElementTree as ET
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        results["is_valid_xml"] = True

        # Routines (from the Routines section, not Flow references)
        routines_section = root.find("Routines")
        if routines_section is not None:
            routines = routines_section.findall("Routine")
        else:
            routines = root.findall(".//Routine")
        results["routine_names"] = [r.get("name", "") for r in routines]
        results["routine_count"] = len(routines)

        # Loops
        loops = root.findall(".//LoopInitiator")
        results["loop_count"] = len(loops)
        for loop in loops:
            for param in loop:
                if param.get("name") == "conditionsFile":
                    val = param.get("val", "")
                    if val:
                        results["loop_conditions_files"].append(val)

        # Components
        comp_names = []
        comp_types = []
        for routine in routines:
            for comp in routine:
                cname = comp.get("name", "")
                ctype = comp.tag
                if cname:
                    comp_names.append(cname)
                    comp_types.append(ctype)
                # Check specific component types
                if ctype == "CodeComponent":
                    results["has_code_component"] = True
                    # Extract code content from all code tabs
                    code_parts = []
                    for param in comp:
                        pname = param.get("name", "")
                        pval = param.get("val", "")
                        if pname in ("Begin Experiment", "Begin Routine", "Each Frame",
                                     "End Routine", "End Experiment",
                                     "Before Experiment", "Before Routine",
                                     "Each Frame", "End Routine", "End Experiment") and pval.strip():
                            code_parts.append(f"# {pname}:\n{pval}")
                    results["code_content"] = "\n".join(code_parts)
                elif ctype == "KeyboardComponent":
                    results["has_keyboard_component"] = True
                    for param in comp:
                        if param.get("name") == "allowedKeys":
                            results["keyboard_allowed_keys"].append(param.get("val", ""))
                elif "Text" in ctype:
                    results["has_text_component"] = True

        results["component_names"] = comp_names
        results["component_types"] = comp_types

        # Params and lines
        results["param_count"] = len(root.findall(".//Param"))
        with open(EXP_FILE, "r") as f:
            results["line_count"] = sum(1 for _ in f)

        # Flow elements
        flow = root.find(".//Flow")
        if flow is not None:
            results["flow_element_count"] = len(list(flow))

    except Exception as e:
        results["is_valid_xml"] = False
        results["xml_parse_error"] = str(e)

# ---- Check Conditions File ----
cond_path = None
if os.path.isfile(COND_FILE):
    cond_path = COND_FILE
elif os.path.isfile(COND_FILE_ALT):
    cond_path = COND_FILE_ALT

if cond_path:
    results["cond_file_exists"] = True
    results["cond_file_path"] = cond_path
    results["cond_file_size"] = os.path.getsize(cond_path)
    mtime = int(os.path.getmtime(cond_path))
    if mtime > results["task_start_time"]:
        results["cond_file_modified"] = True

    try:
        with open(cond_path, "r", encoding="utf-8-sig") as f:
            reader = csv.DictReader(f)
            headers = [h.strip() for h in (reader.fieldnames or [])]
            results["csv_columns"] = headers
            rows = list(reader)
            results["csv_row_count"] = len(rows)

            results["csv_cue_types"] = sorted(set(r.get("cue_type", "").strip() for r in rows if r.get("cue_type")))
            results["csv_flanker_types"] = sorted(set(r.get("flanker_type", "").strip() for r in rows if r.get("flanker_type")))
            results["csv_target_locations"] = sorted(set(r.get("target_location", "").strip() for r in rows if r.get("target_location")))
            results["csv_target_directions"] = sorted(set(r.get("target_direction", "").strip() for r in rows if r.get("target_direction")))
            results["csv_corrAns_values"] = sorted(set(r.get("corrAns", "").strip() for r in rows if r.get("corrAns")))

            # Check if corrAns matches target_direction
            matches = True
            for r in rows:
                td = r.get("target_direction", "").strip()
                ca = r.get("corrAns", "").strip()
                if td and ca and td != ca:
                    matches = False
                    break
            results["csv_corrAns_matches_direction"] = matches
    except Exception as e:
        results["csv_parse_error"] = str(e)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_ant_experiment_result.json
echo "=== Export complete ==="
