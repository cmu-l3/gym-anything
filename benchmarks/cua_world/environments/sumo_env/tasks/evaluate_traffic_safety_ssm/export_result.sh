#!/bin/bash
echo "=== Exporting evaluate_traffic_safety_ssm result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Python script to safely parse XML and extract results
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 << EOF
import xml.etree.ElementTree as ET
import json
import os

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_exists": False,
    "config_created_during_task": False,
    "tripinfo_exists": False,
    "tripinfo_created_during_task": False,
    "ssm_xml_exists": False,
    "ssm_xml_created_during_task": False,
    "ssm_log_found": False,
    "measures_found": [],
    "conflict_count": -1,
    "agent_count": -1,
    "screenshot_path": "/tmp/task_final.png"
}

# 1. Check Config File
config_path = "/home/ga/SUMO_Scenarios/bologna_pasubio/run_ssm.sumocfg"
if os.path.exists(config_path):
    result["config_exists"] = True
    mtime = os.path.getmtime(config_path)
    if mtime > result["task_start"]:
        result["config_created_during_task"] = True

# 2. Check Tripinfo File (verifies simulation successfully ran)
tripinfo_path = "/home/ga/SUMO_Output/tripinfos.xml"
if os.path.exists(tripinfo_path):
    result["tripinfo_exists"] = True
    mtime = os.path.getmtime(tripinfo_path)
    if mtime > result["task_start"]:
        result["tripinfo_created_during_task"] = True

# 3. Check SSM Output File
ssm_path = "/home/ga/SUMO_Output/ssm.xml"
if os.path.exists(ssm_path):
    result["ssm_xml_exists"] = True
    mtime = os.path.getmtime(ssm_path)
    if mtime > result["task_start"]:
        result["ssm_xml_created_during_task"] = True
        
    try:
        tree = ET.parse(ssm_path)
        root = tree.getroot()
        if root.tag == "SSMLog":
            result["ssm_log_found"] = True
            
            # Check tracked measures
            gm = root.find("globalMeasures")
            if gm is not None:
                measures = gm.get("measures", "")
                result["measures_found"] = measures.split()
            
            # Count actual conflicts
            conflicts = root.findall(".//conflict")
            result["conflict_count"] = len(conflicts)
    except Exception as e:
        pass

# 4. Check Agent's Count Output
agent_count_path = "/home/ga/SUMO_Output/conflict_count.txt"
if os.path.exists(agent_count_path):
    try:
        with open(agent_count_path, "r") as f:
            content = f.read().strip()
            # Try to parse the first integer-like block
            if content.isdigit():
                result["agent_count"] = int(content)
            else:
                # Handle cases where agent wrote text + number
                words = content.replace('\\n', ' ').split()
                for w in words:
                    if w.isdigit():
                        result["agent_count"] = int(w)
                        break
    except Exception:
        pass

# Write result JSON
with open("$TEMP_JSON", "w") as f:
    json.dump(result, f)
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="