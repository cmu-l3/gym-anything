#!/bin/bash
echo "=== Exporting debug_broken_experiment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import datetime

OUTPUT_FILE = "/home/ga/PsychoPyExperiments/stroop_fixed.psyexp"
RESULT_FILE = "/tmp/debug_broken_experiment_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "is_valid_xml": False,
    "result_nonce": "",
    "task_start_time": 0,
    "timestamp": datetime.datetime.now().isoformat(),
    # Bug fix checks
    "color_ref_fixed": False,        # Bug 1: $colour -> $letterColor
    "color_ref_value": "",
    "allowed_keys_fixed": False,     # Bug 2: empty -> valid keys
    "allowed_keys_value": "",
    "flow_order_fixed": False,       # Bug 3: instructions before trial
    "routine_order": [],
    "nreps_fixed": False,            # Bug 4: 0 -> positive number
    "nreps_value": "",
    "conditions_file_fixed": False,  # Bug 5: wrong filename -> correct
    "conditions_file_value": "",
    # Structural metrics
    "param_count": 0,
    "line_count": 0,
    "routine_count": 0,
    "has_instructions_routine": False,
    "has_trial_routine": False,
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

if os.path.isfile(OUTPUT_FILE):
    results["file_exists"] = True

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
        if routines is not None:
            results["routine_count"] = len(list(routines))

            for routine in routines:
                rname = routine.get("name", routine.tag).lower()

                if rname == "instructions":
                    results["has_instructions_routine"] = True

                elif rname == "trial":
                    results["has_trial_routine"] = True
                    # Check Bug 1: color reference
                    for comp in routine:
                        for param in comp:
                            pname = param.get("name", "")
                            pval = param.get("val", "")
                            if pname == "color" and pval.startswith("$"):
                                results["color_ref_value"] = pval
                                if "lettercolor" in pval.lower():
                                    results["color_ref_fixed"] = True

                    # Check Bug 2: allowedKeys
                    for comp in routine:
                        cname = comp.get("name", "").lower()
                        if "key" in comp.tag.lower() or "resp" in cname:
                            for param in comp:
                                pname = param.get("name", "")
                                pval = param.get("val", "")
                                if pname == "allowedKeys":
                                    results["allowed_keys_value"] = pval
                                    # Must have at least 2 valid keys
                                    if pval and len(pval.strip()) > 2:
                                        results["allowed_keys_fixed"] = True

        # Check flow ordering (Bug 3) and loop params (Bug 4, 5)
        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            routine_order = []
            for elem in flow:
                if elem.tag == "Routine":
                    routine_order.append(elem.get("name", ""))
                elif "Loop" in elem.tag:
                    for param in elem:
                        pname = param.get("name", "")
                        pval = param.get("val", "")
                        if pname == "nReps":
                            results["nreps_value"] = pval.strip()
                            try:
                                if float(pval.strip()) > 0:
                                    results["nreps_fixed"] = True
                            except:
                                pass
                        if pname == "conditionsFile":
                            results["conditions_file_value"] = pval.strip()
                            if "stroop_conditions" in pval.lower():
                                results["conditions_file_fixed"] = True

            results["routine_order"] = routine_order

            # Check if instructions before trial
            instr_idx = -1
            trial_idx = -1
            for i, rname in enumerate(routine_order):
                if rname.lower() == "instructions" and instr_idx < 0:
                    instr_idx = i
                if rname.lower() == "trial" and trial_idx < 0:
                    trial_idx = i
            if instr_idx >= 0 and trial_idx >= 0 and instr_idx < trial_idx:
                results["flow_order_fixed"] = True

    except Exception as e:
        print(f"XML analysis error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/debug_broken_experiment_result.json
echo "=== Export complete ==="
