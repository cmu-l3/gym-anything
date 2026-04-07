#!/bin/bash
echo "=== Exporting create_self_paced_reading result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# We use Python to parse the .psyexp file and generate a JSON summary.
# This avoids complex bash parsing and allows checking for Code component content.
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess

OUTPUT_FILE = "/home/ga/PsychoPyExperiments/self_paced_reading.psyexp"
CONDITIONS_FILE = "/home/ga/PsychoPyExperiments/conditions/spr_sentences.csv"
RESULT_FILE = "/tmp/create_self_paced_reading_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "file_size": 0,
    "is_valid_xml": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    "routines": [],
    "loop_file_ref": "",
    "code_content_snippets": [],
    "component_counts": {"Code": 0, "Text": 0, "Keyboard": 0},
    "has_split_logic": False,
    "has_feedback_logic": False
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
    results["file_size"] = os.path.getsize(OUTPUT_FILE)
    
    mtime = int(os.path.getmtime(OUTPUT_FILE))
    if mtime > results["task_start_time"]:
        results["file_modified"] = True

    try:
        import xml.etree.ElementTree as ET
        tree = ET.parse(OUTPUT_FILE)
        root = tree.getroot()

        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["is_valid_xml"] = True

        # Analyze Routines
        routines = root.find("Routines") or root.find(".//Routines")
        if routines is not None:
            for routine in routines:
                rname = routine.get("name", "unknown")
                results["routines"].append(rname)
                
                for comp in routine:
                    ctype = comp.tag
                    if "Code" in ctype:
                        results["component_counts"]["Code"] += 1
                        # Check code content for keywords
                        for param in comp:
                            val = param.get("val", "")
                            if val:
                                results["code_content_snippets"].append(val[:50]) # store brief snippet
                                if ".split" in val or "split(" in val:
                                    results["has_split_logic"] = True
                                if "correct" in val.lower() or "corrAns" in val:
                                    results["has_feedback_logic"] = True
                    elif "Text" in ctype:
                        results["component_counts"]["Text"] += 1
                    elif "Key" in ctype or "Keyboard" in ctype:
                        results["component_counts"]["Keyboard"] += 1

        # Analyze Loops
        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            for elem in flow:
                if "Loop" in elem.tag:
                    for param in elem:
                        if param.get("name") == "conditionsFile":
                            results["loop_file_ref"] = param.get("val", "")

    except Exception as e:
        print(f"XML parsing error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_self_paced_reading_result.json
echo "=== Export complete ==="