#!/bin/bash
echo "=== Exporting analyze_intersection_queues result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "Generating independent ground truth scenario to prevent spoofing..."
mkdir -p /tmp/gt_scenario
# Use pristine data to guarantee a reliable baseline execution
cp -r /workspace/data/bologna_pasubio/* /tmp/gt_scenario/

# Safely inject the queue-output command into the ground truth SUMO config
awk '/<output>/ {print; print "        <queue-output value=\"gt_queues.xml\"/>"; next}1' /tmp/gt_scenario/run.sumocfg > /tmp/gt_scenario/run.sumocfg.tmp
mv /tmp/gt_scenario/run.sumocfg.tmp /tmp/gt_scenario/run.sumocfg

# Run ground truth simulation
echo "Executing ground truth simulation..."
sumo -c /tmp/gt_scenario/run.sumocfg --no-step-log true > /dev/null 2>&1

echo "Parsing results and generating export JSON..."
# Use Python to evaluate the outputs safely and collect results
python3 << 'EOF'
import json
import os
import xml.etree.ElementTree as ET

result = {
    "task_start": 0,
    "task_end": 0,
    "config_modified": False,
    "queues_xml_exists": False,
    "queues_xml_mtime": 0,
    "report_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "gt_max_length": -1.0,
    "gt_max_lane": "",
    "gt_max_time": -1.0,
    "gt_error": None
}

if os.path.exists("/tmp/task_start_time.txt"):
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            result["task_start"] = int(f.read().strip())
    except Exception:
        pass

try:
    result["task_end"] = int(os.popen("date +%s").read().strip())
except Exception:
    pass

# 1. Check if agent modified config properly
cfg_path = "/home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg"
if os.path.exists(cfg_path):
    try:
        with open(cfg_path, 'r') as f:
            content = f.read()
            if "queue-output" in content or "queues.xml" in content:
                result["config_modified"] = True
    except Exception:
        pass

# 2. Check if agent output XML was generated
q_path = "/home/ga/SUMO_Output/queues.xml"
if os.path.exists(q_path):
    result["queues_xml_exists"] = True
    result["queues_xml_mtime"] = int(os.path.getmtime(q_path))

# 3. Read the agent's summary report
r_path = "/home/ga/SUMO_Output/queue_report.txt"
if os.path.exists(r_path):
    result["report_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(r_path))
    try:
        with open(r_path, 'r') as f:
            result["report_content"] = f.read()
    except Exception:
        pass

# 4. Extract ground truth metrics natively to verify agent's numbers
gt_q_path = "/tmp/gt_scenario/gt_queues.xml"
if os.path.exists(gt_q_path):
    try:
        tree = ET.parse(gt_q_path)
        root = tree.getroot()
        max_len = -1.0
        max_lane = ""
        max_time = -1.0
        
        # Sequentially parse per standard tie-breaking rules
        for data in root.findall('data'):
            timestep = float(data.get('timestep', 0))
            for lanes in data.findall('lanes'):
                for lane in lanes.findall('lane'):
                    qlen = float(lane.get('queueing_length', 0))
                    if qlen > max_len:
                        max_len = qlen
                        max_lane = lane.get('id', "")
                        max_time = timestep
                    elif qlen == max_len and max_len >= 0:
                        if timestep < max_time:
                            max_time = timestep
                            max_lane = lane.get('id', "")
                            
        result["gt_max_length"] = max_len
        result["gt_max_lane"] = max_lane
        result["gt_max_time"] = max_time
    except Exception as e:
        result["gt_error"] = str(e)

# Save the consolidated payload securely
with open("/tmp/task_result.json.tmp", "w") as f:
    json.dump(result, f, indent=2)
EOF

mv /tmp/task_result.json.tmp /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="