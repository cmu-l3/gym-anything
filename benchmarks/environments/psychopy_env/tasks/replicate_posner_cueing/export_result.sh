#!/bin/bash
echo "=== Exporting replicate_posner_cueing result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import csv

PSYEXP_FILE = "/home/ga/PsychoPyExperiments/posner_cueing_experiment.psyexp"
CONDITIONS_FILE = "/home/ga/PsychoPyExperiments/conditions/posner_conditions.csv"
RESULT_FILE = "/tmp/replicate_posner_cueing_result.json"

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
    "param_count": 0,
    "line_count": 0,
    # Routine checks
    "has_instructions_routine": False,
    "has_fixation_routine": False,
    "has_cue_routine": False,
    "has_target_routine": False,
    "has_debrief_routine": False,
    # Conditions file checks
    "conditions_columns": [],
    "conditions_row_count": 0,
    "has_cue_location_column": False,
    "has_target_location_column": False,
    "has_cue_validity_column": False,
    "has_corrAns_column": False,
    "validity_types": [],
    "has_valid_trials": False,
    "has_invalid_trials": False,
    "has_neutral_trials": False,
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
            results["has_cue_location_column"] = any("cue" in c and ("loc" in c or "pos" in c or "side" in c) for c in col_lower)
            results["has_target_location_column"] = any("target" in c and ("loc" in c or "pos" in c or "side" in c) for c in col_lower)
            results["has_cue_validity_column"] = any("valid" in c for c in col_lower)
            results["has_corrAns_column"] = any("corrans" in c or "correct" in c for c in col_lower)

            rows = list(reader)
            results["conditions_row_count"] = len(rows)

            # Check validity types
            val_col = None
            for c in columns:
                if "valid" in c.lower():
                    val_col = c
                    break

            if val_col:
                vtypes = set()
                for r in rows:
                    v = r.get(val_col, "").strip().lower()
                    vtypes.add(v)
                    if v == "valid":
                        results["has_valid_trials"] = True
                    elif v == "invalid":
                        results["has_invalid_trials"] = True
                    elif v == "neutral":
                        results["has_neutral_trials"] = True
                results["validity_types"] = sorted(vtypes)
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
                if "fixation" in rname_lower or "fix" == rname_lower:
                    results["has_fixation_routine"] = True
                if "cue" in rname_lower:
                    results["has_cue_routine"] = True
                if "target" in rname_lower or "response" in rname_lower:
                    results["has_target_routine"] = True
                if "debrief" in rname_lower or "end" in rname_lower or "thanks" in rname_lower:
                    results["has_debrief_routine"] = True

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

cat /tmp/replicate_posner_cueing_result.json
echo "=== Export complete ==="
