#!/bin/bash
echo "=== Exporting multimodal_person_trip_analysis result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import json
import os
import xml.etree.ElementTree as ET
from datetime import datetime

WORK_DIR = "/home/ga/SUMO_Scenarios/bologna_acosta"
OUTPUT_DIR = "/home/ga/SUMO_Output"
RESULT_PATH = "/tmp/multimodal_person_trip_analysis_result.json"

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
    "modal_perf_exists": False,
    "modal_perf_content": "",
    "modal_perf_rows": 0,
    "bus_stop_analysis_exists": False,
    "bus_stop_analysis_content": "",
    "bus_stop_analysis_rows": 0,
    "underserved_exists": False,
    "underserved_content": "",
    "underserved_rows": 0,
    "new_bus_route_exists": False,
    "new_bus_route_size": 0,
    "new_bus_vehicle_count": 0,
    "new_bus_stops_served": [],
    "improved_cfg_exists": False,
    "improved_cfg_content": "",
    "report_exists": False,
    "report_content": "",
    "report_length": 0,
    "stop_output_exists": False,
    "stop_output_size": 0,
    "tripinfo_exists": False,
    "initial_data": {},
    "timestamp": datetime.now().isoformat()
}

# Load initial data
try:
    with open("/tmp/multimodal_person_trip_analysis_initial_data.json") as f:
        result["initial_data"] = json.load(f)
except Exception:
    pass

# Check modal performance CSV
path = os.path.join(OUTPUT_DIR, "modal_performance.csv")
if os.path.isfile(path):
    result["modal_perf_exists"] = True
    content = safe_read(path)
    result["modal_perf_content"] = content
    result["modal_perf_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check bus stop analysis CSV
path = os.path.join(OUTPUT_DIR, "bus_stop_analysis.csv")
if os.path.isfile(path):
    result["bus_stop_analysis_exists"] = True
    content = safe_read(path)
    result["bus_stop_analysis_content"] = content
    result["bus_stop_analysis_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check underserved stops CSV
path = os.path.join(OUTPUT_DIR, "underserved_stops.csv")
if os.path.isfile(path):
    result["underserved_exists"] = True
    content = safe_read(path)
    result["underserved_content"] = content
    result["underserved_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check new bus route file
new_route = os.path.join(WORK_DIR, "acosta_new_bus_route.rou.xml")
if os.path.isfile(new_route):
    result["new_bus_route_exists"] = True
    result["new_bus_route_size"] = file_size(new_route)
    try:
        tree = ET.parse(new_route)
        root = tree.getroot()
        vehicles = root.findall('vehicle')
        result["new_bus_vehicle_count"] = len(vehicles)
        stops_served = set()
        for v in vehicles:
            for s in v.findall('stop'):
                bs = s.get('busStop', '')
                if bs:
                    stops_served.add(bs)
        result["new_bus_stops_served"] = list(stops_served)
    except Exception:
        pass

# Check improved sumocfg
improved_cfg = os.path.join(WORK_DIR, "run_improved_transit.sumocfg")
if os.path.isfile(improved_cfg):
    result["improved_cfg_exists"] = True
    result["improved_cfg_content"] = safe_read(improved_cfg)

# Check report
report_path = os.path.join(OUTPUT_DIR, "transit_assessment_report.txt")
if os.path.isfile(report_path):
    result["report_exists"] = True
    content = safe_read(report_path)
    result["report_content"] = content
    result["report_length"] = len(content)

# Check stop_output.xml
stop_out = os.path.join(WORK_DIR, "stop_output.xml")
if os.path.isfile(stop_out):
    result["stop_output_exists"] = True
    result["stop_output_size"] = file_size(stop_out)

# Check tripinfo
for f in os.listdir(WORK_DIR):
    if "tripinfo" in f.lower():
        result["tripinfo_exists"] = True
        break

with open(RESULT_PATH, "w") as f:
    json.dump(result, f, indent=2)

os.chmod(RESULT_PATH, 0o666)
print(json.dumps(result, indent=2))
PYEOF

echo "Result saved to /tmp/multimodal_person_trip_analysis_result.json"
echo "=== Export complete ==="
