#!/bin/bash
echo "=== Exporting create_experiment_battery result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import datetime

PSYEXP_FILE = "/home/ga/PsychoPyExperiments/cognitive_battery.psyexp"
RESULT_FILE = "/tmp/create_experiment_battery_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "is_valid_xml": False,
    "result_nonce": "",
    "task_start_time": 0,
    "timestamp": datetime.datetime.now().isoformat(),
    # Experiment structure
    "routine_names": [],
    "routine_count": 0,
    "param_count": 0,
    "line_count": 0,
    # Loop checks
    "loop_count": 0,
    "loop_conditions_files": [],
    "has_stroop_conditions_ref": False,
    "has_flanker_conditions_ref": False,
    "has_simon_conditions_ref": False,
    # Routine checks
    "has_welcome_routine": False,
    "has_debrief_routine": False,
    "instruction_routine_count": 0,
    "break_routine_count": 0,
    "trial_routine_count": 0,
    # Flow structure
    "flow_element_count": 0,
    "flow_routine_order": [],
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

if os.path.isfile(PSYEXP_FILE):
    results["file_exists"] = True

    with open(PSYEXP_FILE) as f:
        results["line_count"] = sum(1 for _ in f)

    mtime = int(os.path.getmtime(PSYEXP_FILE))
    if mtime > results["task_start_time"]:
        results["file_modified"] = True

    try:
        import xml.etree.ElementTree as ET
        tree = ET.parse(PSYEXP_FILE)
        root = tree.getroot()

        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["is_valid_xml"] = True

        results["param_count"] = len(root.findall(".//*[@name]"))

        # Analyze routines
        routines = root.find("Routines") or root.find(".//Routines")
        if routines is not None:
            routine_names = []
            for routine in routines:
                rname = routine.get("name", routine.tag)
                routine_names.append(rname)
                rname_lower = rname.lower()

                if "welcome" in rname_lower or rname_lower == "intro":
                    results["has_welcome_routine"] = True
                if "debrief" in rname_lower or "end" in rname_lower or "thanks" in rname_lower or "thank" in rname_lower:
                    results["has_debrief_routine"] = True
                if "instruct" in rname_lower:
                    results["instruction_routine_count"] += 1
                if "break" in rname_lower or "rest" in rname_lower or "pause" in rname_lower:
                    results["break_routine_count"] += 1
                if "trial" in rname_lower:
                    results["trial_routine_count"] += 1

            results["routine_names"] = routine_names
            results["routine_count"] = len(routine_names)

        # Analyze flow
        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            flow_routines = []
            loop_count = 0
            conditions_files = []

            for elem in flow:
                if elem.tag == "Routine":
                    flow_routines.append(elem.get("name", ""))
                elif "LoopInit" in elem.tag:
                    loop_count += 1
                    for param in elem:
                        pname = param.get("name", "")
                        pval = param.get("val", "")
                        if pname == "conditionsFile" and pval.strip():
                            cfile = pval.strip().lower()
                            conditions_files.append(pval.strip())
                            if "stroop" in cfile:
                                results["has_stroop_conditions_ref"] = True
                            if "flanker" in cfile:
                                results["has_flanker_conditions_ref"] = True
                            if "simon" in cfile:
                                results["has_simon_conditions_ref"] = True

            results["flow_routine_order"] = flow_routines
            results["flow_element_count"] = len(list(flow))
            results["loop_count"] = loop_count
            results["loop_conditions_files"] = conditions_files

    except Exception as e:
        print(f"XML analysis error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_experiment_battery_result.json
echo "=== Export complete ==="
