#!/bin/bash
echo "=== Exporting modify_demo_experiment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess

OUTPUT_FILE = "/home/ga/PsychoPyExperiments/stroop_modified.psyexp"
RESULT_FILE = "/tmp/modify_demo_experiment_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "file_size": 0,
    "is_valid_xml": False,
    "has_instructions_routine": False,
    "has_instruction_text_in_instructions": False,
    "has_space_key_in_instructions": False,
    "has_loop": False,
    "loop_nreps": "",
    "psychopy_running": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    # Structural complexity
    "param_count": 0,
    "component_count": 0,
    "routine_count": 0,
    "line_count": 0,
    # Stroop derivation check (strengthened: requires 2+ markers + structural depth)
    "has_trial_routine": False,
    "has_stroop_content": False,
    "stroop_marker_count": 0,
    "trial_component_count": 0,
    # Flow ordering check
    "instructions_before_trial": False,
    "routine_order": [],
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

# PsychoPy running
try:
    ps = subprocess.run(["pgrep", "-f", "psychopy"], capture_output=True)
    results["psychopy_running"] = ps.returncode == 0
except:
    pass

if os.path.isfile(OUTPUT_FILE):
    results["file_exists"] = True
    results["file_size"] = os.path.getsize(OUTPUT_FILE)

    with open(OUTPUT_FILE) as f:
        results["line_count"] = sum(1 for _ in f)

    mtime = int(os.path.getmtime(OUTPUT_FILE))
    if mtime > results["task_start_time"]:
        results["file_modified"] = True

    try:
        import xml.etree.ElementTree as ET
        tree = ET.parse(OUTPUT_FILE)
        root = tree.getroot()

        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["is_valid_xml"] = True

        results["param_count"] = len(root.findall(".//*[@name]"))

        # Check routines
        routines = root.find("Routines") or root.find(".//Routines")
        instructions_routine_name = None

        if routines is not None:
            results["routine_count"] = len(list(routines))
            stroop_markers = set()

            for routine in routines:
                rname = routine.get("name", routine.tag)
                rname_lower = rname.lower()

                # Check for instructions routine (exact name, not substring)
                if rname_lower == "instructions":
                    results["has_instructions_routine"] = True
                    instructions_routine_name = rname

                    # Only check text and key within the instructions routine
                    for comp in routine:
                        results["component_count"] += 1
                        for param in comp:
                            pname = param.get("name", "")
                            pval = param.get("val", "")
                            if pname == "text" and "space" in pval.lower():
                                results["has_instruction_text_in_instructions"] = True
                            if pname == "allowedKeys" and "space" in pval.lower():
                                results["has_space_key_in_instructions"] = True

                elif rname_lower == "trial":
                    results["has_trial_routine"] = True
                    for comp in routine:
                        results["component_count"] += 1
                        results["trial_component_count"] += 1

                else:
                    for comp in routine:
                        results["component_count"] += 1

                # Check for Stroop-related content (proves derivation from demo)
                # Track distinct markers: requires 2+ for confident derivation
                for comp in routine:
                    for param in comp:
                        pval = param.get("val", "")
                        pval_lower = pval.lower()
                        if "lettercolor" in pval_lower:
                            stroop_markers.add("letterColor")
                        if "stroop" in pval_lower:
                            stroop_markers.add("stroop")
                        # Only count corrAns outside instructions routine
                        if rname_lower != "instructions" and "corrans" in pval_lower:
                            stroop_markers.add("corrAns")

            results["stroop_marker_count"] = len(stroop_markers)
            if len(stroop_markers) >= 2:
                results["has_stroop_content"] = True

        # Check flow ordering
        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            routine_order = []
            for elem in flow:
                if elem.tag == "Routine":
                    rname = elem.get("name", "")
                    routine_order.append(rname)
                elif "Loop" in elem.tag:
                    results["has_loop"] = True
                    for param in elem:
                        pname = param.get("name", "")
                        pval = param.get("val", "")
                        if pname == "nReps":
                            results["loop_nreps"] = pval.strip()

            results["routine_order"] = routine_order

            # Check if instructions comes before trial in flow
            instr_idx = -1
            trial_idx = -1
            for i, rname in enumerate(routine_order):
                if rname.lower() == "instructions" and instr_idx < 0:
                    instr_idx = i
                if rname.lower() == "trial" and trial_idx < 0:
                    trial_idx = i
            if instr_idx >= 0 and (trial_idx < 0 or instr_idx < trial_idx):
                results["instructions_before_trial"] = True

    except Exception as e:
        print(f"XML analysis error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/modify_demo_experiment_result.json
echo "=== Export complete ==="
