#!/bin/bash
echo "=== Exporting create_stroop_experiment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis - avoids spawning Python 5-7 times
python3 << 'PYEOF'
import json
import os
import sys

EXPERIMENT_FILE = "/home/ga/PsychoPyExperiments/stroop_experiment.psyexp"
RESULT_FILE = "/tmp/create_stroop_experiment_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "file_size": 0,
    "is_valid_xml": False,
    "has_routine": False,
    "has_trial_routine": False,
    "has_text_component": False,
    "has_keyboard_component": False,
    "has_loop": False,
    "has_conditions_ref": False,
    "psychopy_running": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": "",
    # Structural complexity metrics (anti-gaming)
    "param_count": 0,
    "component_count": 0,
    "line_count": 0,
    # Component parameter validation
    "text_uses_variable": False,
    "text_uses_color_variable": False,
    "keyboard_has_correct_ans": False,
    "keyboard_allowed_keys": "",
    "loop_nreps": "",
    "windows": "",
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

# Timestamp
import datetime
results["timestamp"] = datetime.datetime.now().isoformat()

# Window list
import subprocess
try:
    wl = subprocess.run(["wmctrl", "-l"], capture_output=True, text=True,
                        env={**os.environ, "DISPLAY": ":1"})
    results["windows"] = wl.stdout.replace("\n", " ").strip()
except:
    pass

# PsychoPy running
try:
    ps = subprocess.run(["pgrep", "-f", "psychopy"], capture_output=True)
    results["psychopy_running"] = ps.returncode == 0
except:
    pass

if os.path.isfile(EXPERIMENT_FILE):
    results["file_exists"] = True
    results["file_size"] = os.path.getsize(EXPERIMENT_FILE)

    # Line count
    with open(EXPERIMENT_FILE) as f:
        results["line_count"] = sum(1 for _ in f)

    # Check modification time
    mtime = int(os.path.getmtime(EXPERIMENT_FILE))
    if mtime > results["task_start_time"]:
        results["file_modified"] = True

    # XML parsing
    try:
        import xml.etree.ElementTree as ET
        tree = ET.parse(EXPERIMENT_FILE)
        root = tree.getroot()

        # Valid PsychoPy XML?
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["is_valid_xml"] = True

        # Count all Param elements (structural complexity)
        results["param_count"] = len(root.findall(".//*[@name]"))

        # Check routines
        routines = root.find("Routines") or root.find(".//Routines")
        if routines is not None:
            for routine in routines:
                results["has_routine"] = True
                rname = routine.get("name", routine.tag).lower()
                if rname == "trial":
                    results["has_trial_routine"] = True

                for comp in routine:
                    results["component_count"] += 1
                    comp_type = comp.tag

                    if "Text" in comp_type:
                        results["has_text_component"] = True
                        # Check if text uses a variable reference ($text)
                        for param in comp:
                            pname = param.get("name", "")
                            pval = param.get("val", "")
                            if pname == "text" and "$" in pval:
                                results["text_uses_variable"] = True
                            if pname == "color" and "$" in pval:
                                results["text_uses_color_variable"] = True

                    if "Key" in comp_type or "Keyboard" in comp_type:
                        results["has_keyboard_component"] = True
                        for param in comp:
                            pname = param.get("name", "")
                            pval = param.get("val", "")
                            if pname == "correctAns" or pname == "corrAns":
                                if "$" in pval or "corrAns" in pval:
                                    results["keyboard_has_correct_ans"] = True
                            if pname == "allowedKeys":
                                results["keyboard_allowed_keys"] = pval.strip()

        # Check flow for loops
        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            for elem in flow:
                if "Loop" in elem.tag:
                    results["has_loop"] = True
                    for param in elem:
                        pname = param.get("name", "")
                        pval = param.get("val", "")
                        if pname == "conditionsFile":
                            if "stroop_conditions" in pval.lower():
                                results["has_conditions_ref"] = True
                        if pname == "nReps":
                            results["loop_nreps"] = pval.strip()

    except Exception as e:
        print(f"XML analysis error: {e}", file=sys.stderr)

# Write result JSON with proper escaping
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

# Set permissions
os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_stroop_experiment_result.json
echo "=== Export complete ==="
