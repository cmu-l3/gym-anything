#!/bin/bash
echo "=== Exporting implement_go_nogo_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import csv

PSYEXP_FILE = "/home/ga/PsychoPyExperiments/go_nogo_experiment.psyexp"
CONDITIONS_FILE = "/home/ga/PsychoPyExperiments/conditions/go_nogo_conditions.csv"
RESULT_FILE = "/tmp/implement_go_nogo_task_result.json"

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
    "has_stimColor_column": False,
    "has_trial_type_column": False,
    "has_corrAns_column": False,
    "go_trial_count": 0,
    "nogo_trial_count": 0,
    "go_nogo_ratio_valid": False,
    "has_green_go": False,
    "has_red_nogo": False,
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

            col_lower = {c.lower().strip(): c for c in columns}
            results["has_stimColor_column"] = any("color" in c or "colour" in c for c in col_lower)
            results["has_trial_type_column"] = any("trial" in c and "type" in c for c in col_lower)
            results["has_corrAns_column"] = any("corrans" in c or "correct" in c for c in col_lower)

            rows = list(reader)
            results["conditions_row_count"] = len(rows)

            # Count go vs nogo
            type_col = None
            for c in columns:
                if "trial" in c.lower() and "type" in c.lower():
                    type_col = c
                    break

            color_col = None
            for c in columns:
                if "color" in c.lower() or "colour" in c.lower():
                    color_col = c
                    break

            go_count = 0
            nogo_count = 0
            for r in rows:
                if type_col:
                    tt = r.get(type_col, "").strip().lower()
                    if tt == "go":
                        go_count += 1
                    elif "nogo" in tt or "no-go" in tt or "no_go" in tt:
                        nogo_count += 1

                if color_col:
                    color = r.get(color_col, "").strip().lower()
                    if type_col:
                        tt = r.get(type_col, "").strip().lower()
                        if "green" in color and tt == "go":
                            results["has_green_go"] = True
                        if "red" in color and ("nogo" in tt or "no-go" in tt or "no_go" in tt):
                            results["has_red_nogo"] = True

            results["go_trial_count"] = go_count
            results["nogo_trial_count"] = nogo_count
            total = go_count + nogo_count
            if total > 0 and go_count > nogo_count:
                results["go_nogo_ratio_valid"] = True
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
                if "debrief" in rname_lower or "end" in rname_lower or "thanks" in rname_lower:
                    results["has_debrief_routine"] = True

                for comp in routine:
                    if "code" in comp.tag.lower():
                        results["has_code_component"] = True

            results["routine_names"] = routine_names
            results["routine_count"] = len(routine_names)

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
            results["loop_count"] = loop_count

    except Exception as e:
        print(f"XML analysis error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/implement_go_nogo_task_result.json
echo "=== Export complete ==="
