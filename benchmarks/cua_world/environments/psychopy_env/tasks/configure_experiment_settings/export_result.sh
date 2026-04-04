#!/bin/bash
echo "=== Exporting configure_experiment_settings result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess

OUTPUT_FILE = "/home/ga/PsychoPyExperiments/attention_study.psyexp"
RESULT_FILE = "/tmp/configure_experiment_settings_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "file_size": 0,
    "is_valid_xml": False,
    "has_exp_name": False,
    "exp_name_value": "",
    "has_fullscr_false": False,
    "has_window_size": False,
    "window_size_value": "",
    "has_data_filename": False,
    "data_filename_value": "",
    "psychopy_running": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    # Structural complexity metrics
    "param_count": 0,
    "line_count": 0,
    "settings_param_count": 0,
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

        settings = root.find("Settings") or root.find(".//Settings")
        if settings is not None:
            results["settings_param_count"] = len(list(settings))

            for param in settings:
                pname = param.get("name", "")
                pval = param.get("val", "")

                # Experiment name - exact match
                if pname == "expName" and pval.strip() == "AttentionStudy":
                    results["has_exp_name"] = True
                    results["exp_name_value"] = pval.strip()

                # Full-screen setting
                if pname in ("Full-screen window", "fullScr"):
                    if pval.strip().lower() == "false":
                        results["has_fullscr_false"] = True

                # Window size - validate order: must be [1024, 768] not [768, 1024]
                if pname in ("Window size (pixels)", "size"):
                    results["window_size_value"] = pval.strip()
                    # Accept formats: [1024, 768], (1024, 768), 1024, 768
                    cleaned = pval.replace("[", "").replace("]", "").replace("(", "").replace(")", "").strip()
                    parts = [p.strip() for p in cleaned.split(",")]
                    if len(parts) == 2 and parts[0] == "1024" and parts[1] == "768":
                        results["has_window_size"] = True

                # Data filename - only in actual data filename params
                # Must NOT match PsychoPy's default template blindly
                if pname in ("Data filename", "dataFileName"):
                    results["data_filename_value"] = pval.strip()
                    # Check that the pattern was intentionally configured
                    # Default PsychoPy template uses: u"data/%s_%s_%s" % (expInfo['participant'], expName, expInfo['date'])
                    # Award points only if it contains a participant reference
                    if "participant" in pval.lower():
                        results["has_data_filename"] = True

    except Exception as e:
        print(f"XML analysis error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/configure_experiment_settings_result.json
echo "=== Export complete ==="
