#!/bin/bash
echo "=== Exporting freight_corridor_capacity_analysis result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import json
import os
import glob
import re
from datetime import datetime

OUTPUT_DIR = "/home/ga/SUMO_Output"
WORK_DIR = "/home/ga/SUMO_Scenarios/bologna_acosta"
RESULT_PATH = "/tmp/freight_corridor_capacity_analysis_result.json"

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
    "report_exists": False,
    "report_rows": 0,
    "report_content": "",
    "recommendation_exists": False,
    "recommendation_length": 0,
    "recommendation_content": "",
    "truck_routes_exist": False,
    "truck_route_files": "",
    "modified_config": False,
    "modified_tripinfo_exists": False,
    "modified_tripinfo_size": 0,
    "truck_vehicle_count": 0,
    "baseline_stats": {},
    "timestamp": datetime.now().isoformat()
}

# Check report CSV
report_path = os.path.join(OUTPUT_DIR, "corridor_capacity_report.csv")
if os.path.isfile(report_path):
    result["report_exists"] = True
    content = safe_read(report_path)
    result["report_content"] = content
    result["report_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check recommendation
rec_path = os.path.join(OUTPUT_DIR, "corridor_recommendation.txt")
if os.path.isfile(rec_path):
    result["recommendation_exists"] = True
    content = safe_read(rec_path)
    result["recommendation_content"] = content
    result["recommendation_length"] = len(content)

# Collect all candidate files (deduplicated)
candidate_files = set()
for pattern in [os.path.join(WORK_DIR, "*.rou.xml"), os.path.join(WORK_DIR, "truck*.xml"),
                os.path.join(WORK_DIR, "freight*.xml"), os.path.join(WORK_DIR, "*truck*.rou.xml"),
                os.path.join(OUTPUT_DIR, "*.rou.xml"), os.path.join(OUTPUT_DIR, "*.xml")]:
    for f in glob.glob(pattern):
        candidate_files.add(f)

# Check for truck route files
truck_route_files = set()
for f in candidate_files:
    content = safe_read(f)
    if re.search(r'truck|trailer|heavy|freight|hgv|HDV', content, re.IGNORECASE):
        truck_route_files.add(os.path.basename(f))

if truck_route_files:
    result["truck_routes_exist"] = True
    result["truck_route_files"] = ",".join(truck_route_files)

# Check for modified sumocfg referencing trucks
cfg_files = set()
for pattern in [os.path.join(WORK_DIR, "*.sumocfg"), os.path.join(OUTPUT_DIR, "*.sumocfg")]:
    for f in glob.glob(pattern):
        cfg_files.add(f)
for f in cfg_files:
    content = safe_read(f)
    if re.search(r'truck|freight|heavy', content, re.IGNORECASE):
        result["modified_config"] = True

# Check for tripinfo output (not baseline)
tripinfo_files = set()
for pattern in [os.path.join(WORK_DIR, "tripinfos*.xml"), os.path.join(OUTPUT_DIR, "tripinfos*.xml"),
                os.path.join(WORK_DIR, "trip*.xml")]:
    for f in glob.glob(pattern):
        tripinfo_files.add(f)
for f in tripinfo_files:
    base = os.path.basename(f)
    if base != "tripinfos_baseline.xml":
        fsize = file_size(f)
        if fsize > 100:
            result["modified_tripinfo_exists"] = True
            result["modified_tripinfo_size"] = fsize

# Count truck vehicles in route files (deduplicated)
truck_count = 0
for f in candidate_files:
    content = safe_read(f)
    truck_count += len(re.findall(
        r'type="(?:truck|trailer|heavy|freight|hgv|HDV)|vClass="(?:truck|trailer)',
        content, re.IGNORECASE))
result["truck_vehicle_count"] = truck_count

# Read baseline stats
baseline_stats_path = "/tmp/freight_corridor_baseline_stats.json"
if os.path.isfile(baseline_stats_path):
    try:
        with open(baseline_stats_path) as f:
            result["baseline_stats"] = json.load(f)
    except Exception:
        pass

with open(RESULT_PATH, "w") as f:
    json.dump(result, f, indent=2)

os.chmod(RESULT_PATH, 0o666)
print(json.dumps(result, indent=2))
PYEOF

echo "Result saved to /tmp/freight_corridor_capacity_analysis_result.json"
echo "=== Export complete ==="
