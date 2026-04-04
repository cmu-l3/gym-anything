#!/bin/bash
echo "=== Exporting build_visual_search_experiment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import csv

PSYEXP_FILE = "/home/ga/PsychoPyExperiments/visual_search_experiment.psyexp"
CONDITIONS_FILE = "/home/ga/PsychoPyExperiments/conditions/visual_search_conditions.csv"
RESULT_FILE = "/tmp/build_visual_search_experiment_result.json"

results = {
    "psyexp_exists": False,
    "psyexp_modified": False,
    "is_valid_xml": False,
    "conditions_exists": False,
    "conditions_modified": False,
    "result_nonce": "",
    "task_start_time": 0,
    "timestamp": datetime.datetime.now().isoformat(),
    # Experiment structure
    "routine_names": [],
    "routine_count": 0,
    "loop_count": 0,
    "has_conditions_ref": False,
    "conditions_ref_value": "",
    "has_code_component": False,
    "param_count": 0,
    "line_count": 0,
    # Routine checks
    "has_instructions_routine": False,
    "has_practice_routine": False,
    "has_trial_routine": False,
    "has_feedback_routine": False,
    "has_break_routine": False,
    "has_debrief_routine": False,
    # Conditions file checks
    "conditions_columns": [],
    "conditions_row_count": 0,
    "has_set_size_column": False,
    "has_target_present_column": False,
    "has_corrAns_column": False,
    "set_sizes_found": [],
    "has_target_present_values": False,
    "has_target_absent_values": False,
    "corrAns_values": [],
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

# Check conditions file
if os.path.isfile(CONDITIONS_FILE):
    results["conditions_exists"] = True
    mtime = int(os.path.getmtime(CONDITIONS_FILE))
    if mtime > results["task_start_time"]:
        results["conditions_modified"] = True

    try:
        with open(CONDITIONS_FILE, 'r') as f:
            reader = csv.DictReader(f)
            columns = reader.fieldnames or []
            results["conditions_columns"] = list(columns)

            col_lower = [c.lower().strip() for c in columns]
            results["has_set_size_column"] = any("set_size" in c or "setsize" in c for c in col_lower)
            results["has_target_present_column"] = any("target" in c and "present" in c for c in col_lower)
            results["has_corrAns_column"] = any("corrans" in c or "correct" in c for c in col_lower)

            rows = list(reader)
            results["conditions_row_count"] = len(rows)

            # Find set_size column
            set_size_col = None
            for c in columns:
                if "set_size" in c.lower() or "setsize" in c.lower():
                    set_size_col = c
                    break

            if set_size_col:
                sizes = sorted(set(r.get(set_size_col, "").strip() for r in rows if r.get(set_size_col, "").strip()))
                results["set_sizes_found"] = sizes

            # Find target_present column
            tp_col = None
            for c in columns:
                if "target" in c.lower() and "present" in c.lower():
                    tp_col = c
                    break

            if tp_col:
                tp_vals = set(r.get(tp_col, "").strip() for r in rows)
                results["has_target_present_values"] = any(v in ("1", "True", "true", "yes") for v in tp_vals)
                results["has_target_absent_values"] = any(v in ("0", "False", "false", "no") for v in tp_vals)

            # Find corrAns column
            ca_col = None
            for c in columns:
                if "corrans" in c.lower() or "correct" in c.lower():
                    ca_col = c
                    break

            if ca_col:
                results["corrAns_values"] = sorted(set(r.get(ca_col, "").strip() for r in rows if r.get(ca_col, "").strip()))
    except Exception as e:
        print(f"Conditions analysis error: {e}", file=sys.stderr)

# Check .psyexp file
if os.path.isfile(PSYEXP_FILE):
    results["psyexp_exists"] = True

    with open(PSYEXP_FILE) as f:
        results["line_count"] = sum(1 for _ in f)

    mtime = int(os.path.getmtime(PSYEXP_FILE))
    if mtime > results["task_start_time"]:
        results["psyexp_modified"] = True

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

                if "instruct" in rname_lower or "welcome" in rname_lower:
                    results["has_instructions_routine"] = True
                if "practice" in rname_lower or "prac" in rname_lower:
                    results["has_practice_routine"] = True
                if "trial" in rname_lower:
                    results["has_trial_routine"] = True
                if "feedback" in rname_lower or "fb" in rname_lower:
                    results["has_feedback_routine"] = True
                if "break" in rname_lower or "rest" in rname_lower or "pause" in rname_lower:
                    results["has_break_routine"] = True
                if "debrief" in rname_lower or "end" in rname_lower or "thanks" in rname_lower or "thank" in rname_lower or "goodbye" in rname_lower:
                    results["has_debrief_routine"] = True

                # Check for Code components
                for comp in routine:
                    if "code" in comp.tag.lower():
                        results["has_code_component"] = True

            results["routine_names"] = routine_names
            results["routine_count"] = len(routine_names)

        # Analyze flow for loops
        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            loop_count = 0
            for elem in flow:
                if "LoopInit" in elem.tag:
                    loop_count += 1
                    for param in elem:
                        pname = param.get("name", "")
                        pval = param.get("val", "")
                        if pname == "conditionsFile" and pval.strip():
                            results["has_conditions_ref"] = True
                            results["conditions_ref_value"] = pval.strip()
            results["loop_count"] = loop_count

    except Exception as e:
        print(f"XML analysis error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/build_visual_search_experiment_result.json
echo "=== Export complete ==="
