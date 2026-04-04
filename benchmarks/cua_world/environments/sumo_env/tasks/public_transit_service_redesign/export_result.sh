#!/bin/bash
echo "=== Exporting public_transit_service_redesign result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import json
import os
import glob
import re
import filecmp
from datetime import datetime

WORK_DIR = "/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR = "/home/ga/SUMO_Output"
RESULT_PATH = "/tmp/public_transit_service_redesign_result.json"

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
    "current_stop_count": 0,
    "express_bus_count": 0,
    "total_bus_count": 0,
    "person_trip_count": 0,
    "modified_cfg": False,
    "sim_ran": False,
    "tripinfo_size": 0,
    "report_exists": False,
    "report_rows": 0,
    "report_content": "",
    "summary_exists": False,
    "summary_length": 0,
    "summary_content": "",
    "initial_data": {},
    "timestamp": datetime.now().isoformat()
}

# Collect all XML files (deduplicated)
all_xml_files = set()
for pattern in [os.path.join(WORK_DIR, "*.xml"), os.path.join(WORK_DIR, "*.add.xml"),
                os.path.join(WORK_DIR, "*.rou.xml")]:
    for f in glob.glob(pattern):
        all_xml_files.add(f)

# Count current bus stops, bus vehicles, express buses, and person trips
for f in all_xml_files:
    content = safe_read(f)
    result["current_stop_count"] += len(re.findall(r'<busStop ', content))
    result["total_bus_count"] += len(re.findall(r'type="bus"', content))
    result["express_bus_count"] += len(re.findall(r'express|new_line|line_express', content, re.IGNORECASE))
    result["person_trip_count"] += len(re.findall(r'<person ', content))
    result["person_trip_count"] += len(re.findall(r'<personTrip ', content))

# Check for modified simulation config
orig_cfg = "/workspace/data/bologna_pasubio/run.sumocfg"
for pattern in [os.path.join(WORK_DIR, "*.sumocfg"), os.path.join(WORK_DIR, "*.cfg"),
                os.path.join(OUTPUT_DIR, "*.sumocfg")]:
    for f in glob.glob(pattern):
        try:
            if not filecmp.cmp(f, orig_cfg, shallow=False):
                result["modified_cfg"] = True
        except Exception:
            result["modified_cfg"] = True

# Check if simulation ran
tripinfo_path = os.path.join(WORK_DIR, "tripinfos.xml")
if os.path.isfile(tripinfo_path):
    sz = file_size(tripinfo_path)
    if sz > 100:
        result["sim_ran"] = True
        result["tripinfo_size"] = sz

for pattern in [os.path.join(OUTPUT_DIR, "tripinfo*.xml"), os.path.join(WORK_DIR, "*trip*.xml")]:
    for f in glob.glob(pattern):
        sz = file_size(f)
        if sz > 100:
            result["sim_ran"] = True
            result["tripinfo_size"] = max(result["tripinfo_size"], sz)

# Check report
report_path = os.path.join(OUTPUT_DIR, "transit_service_report.csv")
if os.path.isfile(report_path):
    result["report_exists"] = True
    content = safe_read(report_path)
    result["report_content"] = content
    result["report_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check summary
summary_path = os.path.join(OUTPUT_DIR, "transit_redesign_summary.txt")
if os.path.isfile(summary_path):
    result["summary_exists"] = True
    content = safe_read(summary_path)
    result["summary_content"] = content
    result["summary_length"] = len(content)

# Read initial data
initial_data_path = "/tmp/public_transit_initial_data.json"
if os.path.isfile(initial_data_path):
    try:
        with open(initial_data_path) as f:
            result["initial_data"] = json.load(f)
    except Exception:
        pass

with open(RESULT_PATH, "w") as f:
    json.dump(result, f, indent=2)

os.chmod(RESULT_PATH, 0o666)
print(json.dumps(result, indent=2))
PYEOF

echo "Result saved to /tmp/public_transit_service_redesign_result.json"
echo "=== Export complete ==="
