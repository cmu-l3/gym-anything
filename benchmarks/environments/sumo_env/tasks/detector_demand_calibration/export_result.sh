#!/bin/bash
echo "=== Exporting detector_demand_calibration result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import json
import os
import xml.etree.ElementTree as ET
from datetime import datetime

WORK_DIR = "/home/ga/SUMO_Scenarios/bologna_acosta"
OUTPUT_DIR = "/home/ga/SUMO_Output"
RESULT_PATH = "/tmp/detector_demand_calibration_result.json"

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
    "baseline_counts_exists": False,
    "baseline_counts_content": "",
    "baseline_counts_rows": 0,
    "observed_counts_exists": False,
    "observed_counts_content": "",
    "observed_counts_rows": 0,
    "calibrated_route_exists": False,
    "calibrated_route_size": 0,
    "calibrated_vehicle_count": 0,
    "calibrated_cfg_exists": False,
    "calibrated_cfg_content": "",
    "calibrated_counts_exists": False,
    "calibrated_counts_content": "",
    "calibrated_counts_rows": 0,
    "calibration_report_exists": False,
    "calibration_report_content": "",
    "calibration_report_rows": 0,
    "summary_exists": False,
    "summary_content": "",
    "summary_length": 0,
    "e1_output_exists": False,
    "e1_output_size": 0,
    "initial_data": {},
    "timestamp": datetime.now().isoformat()
}

# Load initial data
try:
    with open("/tmp/detector_demand_calibration_initial_data.json") as f:
        result["initial_data"] = json.load(f)
except Exception:
    pass

# Check baseline detector counts CSV
path = os.path.join(OUTPUT_DIR, "baseline_detector_counts.csv")
if os.path.isfile(path):
    result["baseline_counts_exists"] = True
    content = safe_read(path)
    result["baseline_counts_content"] = content
    result["baseline_counts_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check observed counts CSV
path = os.path.join(OUTPUT_DIR, "observed_detector_counts.csv")
if os.path.isfile(path):
    result["observed_counts_exists"] = True
    content = safe_read(path)
    result["observed_counts_content"] = content
    result["observed_counts_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check calibrated route file
cal_route = os.path.join(WORK_DIR, "acosta_calibrated.rou.xml")
if os.path.isfile(cal_route):
    result["calibrated_route_exists"] = True
    result["calibrated_route_size"] = file_size(cal_route)
    try:
        tree = ET.parse(cal_route)
        root = tree.getroot()
        result["calibrated_vehicle_count"] = len(root.findall('vehicle'))
    except Exception:
        pass

# Check calibrated sumocfg
cal_cfg = os.path.join(WORK_DIR, "run_calibrated.sumocfg")
if os.path.isfile(cal_cfg):
    result["calibrated_cfg_exists"] = True
    result["calibrated_cfg_content"] = safe_read(cal_cfg)

# Check calibrated detector counts CSV
path = os.path.join(OUTPUT_DIR, "calibrated_detector_counts.csv")
if os.path.isfile(path):
    result["calibrated_counts_exists"] = True
    content = safe_read(path)
    result["calibrated_counts_content"] = content
    result["calibrated_counts_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check calibration report CSV
path = os.path.join(OUTPUT_DIR, "calibration_report.csv")
if os.path.isfile(path):
    result["calibration_report_exists"] = True
    content = safe_read(path)
    result["calibration_report_content"] = content
    result["calibration_report_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check summary
path = os.path.join(OUTPUT_DIR, "calibration_summary.txt")
if os.path.isfile(path):
    result["summary_exists"] = True
    content = safe_read(path)
    result["summary_content"] = content
    result["summary_length"] = len(content)

# Check e1_output.xml
e1_path = os.path.join(WORK_DIR, "e1_output.xml")
if os.path.isfile(e1_path):
    result["e1_output_exists"] = True
    result["e1_output_size"] = file_size(e1_path)

with open(RESULT_PATH, "w") as f:
    json.dump(result, f, indent=2)

os.chmod(RESULT_PATH, 0o666)
print(json.dumps(result, indent=2))
PYEOF

echo "Result saved to /tmp/detector_demand_calibration_result.json"
echo "=== Export complete ==="
