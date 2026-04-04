#!/bin/bash
echo "=== Exporting traffic_calming_zone_design result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import json
import os
import xml.etree.ElementTree as ET
from datetime import datetime

WORK_DIR = "/home/ga/SUMO_Scenarios/bologna_acosta"
OUTPUT_DIR = "/home/ga/SUMO_Output"
RESULT_PATH = "/tmp/traffic_calming_zone_design_result.json"

def safe_read(path):
    try:
        with open(path, 'r', errors='replace') as f:
            return f.read()
    except Exception:
        return ""

def file_size(path):
    try:
        return os.path.getsize(path)
    except Exception:
        return 0

result = {
    "baseline_exists": False,
    "baseline_size": 0,
    "calming_exists": False,
    "calming_size": 0,
    "network_modified": False,
    "edges_with_30kmh": 0,
    "report_exists": False,
    "report_rows": 0,
    "report_content": "",
    "summary_exists": False,
    "summary_length": 0,
    "summary_content": "",
    "timestamp": datetime.now().isoformat()
}

# Check baseline tripinfo
baseline_path = os.path.join(OUTPUT_DIR, "baseline_tripinfos.xml")
if os.path.isfile(baseline_path):
    result["baseline_exists"] = True
    result["baseline_size"] = file_size(baseline_path)

# Check calming tripinfo
calming_path = os.path.join(OUTPUT_DIR, "calming_tripinfos.xml")
if os.path.isfile(calming_path):
    result["calming_exists"] = True
    result["calming_size"] = file_size(calming_path)

# Check if network was modified (compare speeds to original)
orig_data = {}
try:
    with open("/tmp/traffic_calming_edge_data.json") as f:
        orig_data = json.load(f)
except Exception:
    pass

net_file = os.path.join(WORK_DIR, "acosta_buslanes.net.xml")
count_30kmh = 0
modified = False
try:
    tree = ET.parse(net_file)
    root = tree.getroot()
    for edge in root.findall('edge'):
        eid = edge.get('id', '')
        if eid.startswith(':'):
            continue
        for lane in edge.findall('lane'):
            speed = float(lane.get('speed', 0))
            # 30 km/h = 8.33 m/s, allow tolerance
            if 7.0 <= speed <= 9.0:
                orig = orig_data.get(eid, {})
                if isinstance(orig, dict) and orig.get('max_speed', 0) > 9.0:
                    count_30kmh += 1
                    modified = True
                    break
except Exception:
    pass

result["edges_with_30kmh"] = count_30kmh
result["network_modified"] = modified

# Check report
report_path = os.path.join(OUTPUT_DIR, "traffic_calming_report.csv")
if os.path.isfile(report_path):
    result["report_exists"] = True
    content = safe_read(report_path)
    result["report_content"] = content
    result["report_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check summary
summary_path = os.path.join(OUTPUT_DIR, "traffic_calming_summary.txt")
if os.path.isfile(summary_path):
    result["summary_exists"] = True
    content = safe_read(summary_path)
    result["summary_content"] = content
    result["summary_length"] = len(content)

with open(RESULT_PATH, "w") as f:
    json.dump(result, f, indent=2)

os.chmod(RESULT_PATH, 0o666)
print(json.dumps(result, indent=2))
PYEOF

echo "Result saved to /tmp/traffic_calming_zone_design_result.json"
echo "=== Export complete ==="
