#!/bin/bash
echo "=== Exporting calculate_travel_time_reliability result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Execute Python script to compute ground truth, parse agent's output, and consolidate result JSON
python3 << 'EOF'
import os
import json
import time
import subprocess
import xml.etree.ElementTree as ET

def manual_percentile(data, p):
    if not data: return 0.0
    s = sorted(data)
    k = (len(s) - 1) * (p / 100.0)
    f = int(k)
    c = min(f + 1, len(s) - 1)
    return s[f] if f == c else s[f] + (s[c] - s[f]) * (k - f)

def manual_mean(data):
    return sum(data) / len(data) if data else 0.0

agent_dir = "/home/ga/SUMO_Output"
seeds = [1001, 1002, 1003, 1004, 1005]

# 1. Check Agent's Tripinfo Files
valid_tripinfo_files = 0
agent_total_trips_in_xml = 0

if os.path.exists(agent_dir):
    xml_files = [f for f in os.listdir(agent_dir) if f.endswith('.xml')]
    for xf in xml_files:
        try:
            tree = ET.parse(os.path.join(agent_dir, xf))
            if tree.getroot().tag == 'tripinfos':
                valid_tripinfo_files += 1
                agent_total_trips_in_xml += len(tree.getroot().findall('tripinfo'))
        except Exception:
            pass

# 2. Check Agent's Report JSON
agent_report_path = os.path.join(agent_dir, "reliability_report.json")
agent_report = {}
report_exists = False

if os.path.exists(agent_report_path):
    report_exists = True
    try:
        with open(agent_report_path, 'r') as f:
            agent_report = json.load(f)
    except Exception as e:
        agent_report = {"error": f"invalid json: {e}"}

# 3. Compute Ground Truth Internally (Ensures robust verification without hardcoding values)
base_cfg = "/home/ga/SUMO_Scenarios/bologna_acosta/run.sumocfg"
gt_durations = []

print("Computing ground truth values deterministically...")
for s in seeds:
    out_xml = f"/tmp/gt_tripinfo_{s}.xml"
    subprocess.run([
        "sumo", "-c", base_cfg,
        "--random-depart-offset", "120",
        "--seed", str(s),
        "--tripinfo-output", out_xml
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    if os.path.exists(out_xml):
        try:
            tree = ET.parse(out_xml)
            for trip in tree.getroot().findall("tripinfo"):
                gt_durations.append(float(trip.get("duration")))
        except Exception:
            pass

gt_total = len(gt_durations)
gt_mean = manual_mean(gt_durations)
gt_p95 = manual_percentile(gt_durations, 95)

# 4. Save Task Result
result = {
    "valid_tripinfo_files_count": valid_tripinfo_files,
    "agent_total_trips_in_xml": agent_total_trips_in_xml,
    "report_exists": report_exists,
    "agent_report": agent_report,
    "ground_truth": {
        "total_trips": gt_total,
        "mean_duration": gt_mean,
        "p95_duration": gt_p95
    },
    "timestamp": time.time(),
    "screenshot_path": "/tmp/task_final.png"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Ground truth computed and results bundled successfully.")
EOF

# Correct permissions to allow verifier reading
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="