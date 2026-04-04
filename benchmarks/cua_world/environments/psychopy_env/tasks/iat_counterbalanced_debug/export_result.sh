#!/bin/bash
echo "=== Exporting iat_counterbalanced_debug result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import json, os, sys, datetime
import xml.etree.ElementTree as ET

OUTPUT_FILE = "/home/ga/PsychoPyExperiments/iat_fixed.psyexp"
RESULT_FILE = "/tmp/iat_counterbalanced_debug_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "is_valid_xml": False,
    "result_nonce": "",
    "task_start_time": 0,
    "timestamp": datetime.datetime.now().isoformat(),
    # Bug fix checks
    "bug1_flow_order_fixed": False,       # Block 3 before Block 4
    "bug2_practice_nreps_fixed": False,   # block2 nReps > 0
    "bug3_code_equals_fixed": False,      # == instead of =
    "bug4_color_ref_fixed": False,        # $stim_color instead of $category_color
    "bug5_filename_fixed": False,         # $participant in filename
    "has_debrief_routine": False,         # debrief added at end
    # Detail fields
    "flow_order": [],
    "block2_nreps": "",
    "code_component_each_frame": "",
    "b2_label_color_value": "",
    "data_filename_value": "",
    "routine_names": [],
    "param_count": 0,
    "line_count": 0,
}

try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass
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
        tree = ET.parse(OUTPUT_FILE)
        root = tree.getroot()
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["is_valid_xml"] = True
        results["param_count"] = len(root.findall(".//*[@name]"))

        # Read Settings for Bug 5 (data filename)
        settings = root.find("Settings") or root.find(".//Settings")
        if settings is not None:
            for param in settings:
                pname = param.get("name", "")
                pval = param.get("val", "")
                if pname == "Data filename":
                    results["data_filename_value"] = pval
                    # Fixed: should reference expInfo['participant'] or use $participant
                    if "participant" in pval and ("expInfo['participant']" in pval or "expInfo[\"participant\"]" in pval or "$participant" in pval):
                        results["bug5_filename_fixed"] = True

        # Read routines
        routines = root.find("Routines") or root.find(".//Routines")
        routine_names = []
        if routines is not None:
            for routine in routines:
                rname = routine.get("name", routine.tag)
                routine_names.append(rname)
                rl = rname.lower()

                # Check for debrief routine
                if "debrief" in rl or "debriefing" in rl:
                    results["has_debrief_routine"] = True

                # Bug 4: check b2_label color in b2_trial
                if "b2_trial" in rname or rname == "b2_trial":
                    for comp in routine:
                        cname = comp.get("name", "")
                        if "label" in cname.lower():
                            for param in comp:
                                if param.get("name") == "color":
                                    results["b2_label_color_value"] = param.get("val", "")
                                    val = param.get("val", "").lower()
                                    if "stim_color" in val:
                                        results["bug4_color_ref_fixed"] = True

                # Bug 3: check code component in b3_trial
                if "b3_trial" in rname or rname == "b3_trial":
                    for comp in routine:
                        if "Code" in comp.tag or "code" in comp.get("name","").lower():
                            for param in comp:
                                if param.get("name") == "Each Frame":
                                    code_text = param.get("val", "")
                                    results["code_component_each_frame"] = code_text[:200]
                                    # Fixed: uses == not = for comparison
                                    import re
                                    # Look for if condition with == (not simple assignment)
                                    if re.search(r'if\s+\w+[\.\w]*\s*==\s*0', code_text):
                                        results["bug3_code_equals_fixed"] = True

        results["routine_names"] = routine_names

        # Read Flow for Bug 1 and 2
        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            flow_items = []
            for elem in flow:
                if elem.tag == "Routine":
                    flow_items.append(("routine", elem.get("name", "")))
                elif "LoopInitiator" in elem.tag:
                    loop_name = elem.get("name", "")
                    nreps_val = ""
                    for param in elem:
                        if param.get("name") == "nReps":
                            nreps_val = param.get("val", "")
                        if param.get("name") == "name":
                            loop_name = param.get("val", loop_name)
                    flow_items.append(("loop", loop_name, nreps_val))

            results["flow_order"] = [item[1] if len(item) > 1 else "" for item in flow_items]

            # Check block2 nReps (Bug 2)
            for item in flow_items:
                if item[0] == "loop" and "block2" in item[1].lower():
                    results["block2_nreps"] = item[2] if len(item) > 2 else ""
                    try:
                        if float(item[2]) > 0:
                            results["bug2_practice_nreps_fixed"] = True
                    except:
                        pass

            # Check flow order: block3 before block4 (Bug 1)
            # Find positions of block3 and block4 loops
            b3_pos = -1
            b4_pos = -1
            for i, item in enumerate(flow_items):
                if item[0] == "loop":
                    name_lower = item[1].lower()
                    if "block3" in name_lower or "compatible" in name_lower:
                        if b3_pos < 0:
                            b3_pos = i
                    if "block4" in name_lower or "incompatible" in name_lower:
                        if b4_pos < 0:
                            b4_pos = i
            if b3_pos >= 0 and b4_pos >= 0 and b3_pos < b4_pos:
                results["bug1_flow_order_fixed"] = True

            # Check debrief is at end of flow
            if results["has_debrief_routine"]:
                # It should appear after block4 in the flow
                debrief_pos = -1
                for i, item in enumerate(flow_items):
                    if item[0] == "routine" and "debrief" in item[1].lower():
                        debrief_pos = i
                # The debrief should be near the end (after all experiment blocks)
                if debrief_pos > b4_pos if b4_pos >= 0 else debrief_pos >= 0:
                    results["has_debrief_routine"] = True

    except Exception as e:
        print(f"XML analysis error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)
os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/iat_counterbalanced_debug_result.json
echo "=== Export complete ==="
