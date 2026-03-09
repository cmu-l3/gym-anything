#!/bin/bash
echo "=== Exporting congestion_pricing_scenario result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import json
import os
import xml.etree.ElementTree as ET
from datetime import datetime

WORK_DIR = "/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR = "/home/ga/SUMO_Output"
RESULT_PATH = "/tmp/congestion_pricing_scenario_result.json"

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
    "baseline_econ_exists": False,
    "baseline_econ_content": "",
    "baseline_econ_rows": 0,
    "priced_route_exists": False,
    "priced_route_size": 0,
    "priced_vehicle_count": 0,
    "priced_bus_preserved": False,
    "demand_reduction_pct": 0.0,
    "priced_cfg_exists": False,
    "priced_cfg_content": "",
    "priced_econ_exists": False,
    "priced_econ_content": "",
    "priced_econ_rows": 0,
    "cba_exists": False,
    "cba_content": "",
    "cba_rows": 0,
    "brief_exists": False,
    "brief_content": "",
    "brief_length": 0,
    "initial_data": {},
    "timestamp": datetime.now().isoformat()
}

# Load initial data
try:
    with open("/tmp/congestion_pricing_scenario_initial_data.json") as f:
        result["initial_data"] = json.load(f)
except Exception:
    pass

# Check baseline economics CSV
path = os.path.join(OUTPUT_DIR, "baseline_traffic_economics.csv")
if os.path.isfile(path):
    result["baseline_econ_exists"] = True
    content = safe_read(path)
    result["baseline_econ_content"] = content
    result["baseline_econ_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check priced route file
priced_route = os.path.join(WORK_DIR, "pasubio_priced.rou.xml")
if os.path.isfile(priced_route):
    result["priced_route_exists"] = True
    result["priced_route_size"] = file_size(priced_route)
    try:
        tree = ET.parse(priced_route)
        root = tree.getroot()
        vehicles = root.findall('vehicle')
        result["priced_vehicle_count"] = len(vehicles)

        # Check if bus type vehicles are removed
        bus_types = ['bus']
        priced_types = set(v.get('type', '') for v in vehicles)
        # Check if buses are preserved (they should still be in the bus route file, not this one)
        # The priced route only contains private vehicles
        orig_private = result.get("initial_data", {}).get("private_vehicle_count", 0)
        if orig_private > 0 and len(vehicles) > 0:
            reduction = (orig_private - len(vehicles)) / orig_private * 100
            result["demand_reduction_pct"] = round(reduction, 1)
            # Buses should NOT appear in the priced route (they're separate)
            has_bus = any(v.get('type', '') == 'bus' for v in vehicles)
            if not has_bus:
                result["priced_bus_preserved"] = True
    except Exception as e:
        result["priced_route_error"] = str(e)

# Check priced sumocfg
priced_cfg = os.path.join(WORK_DIR, "run_priced.sumocfg")
if os.path.isfile(priced_cfg):
    result["priced_cfg_exists"] = True
    result["priced_cfg_content"] = safe_read(priced_cfg)

# Check priced economics CSV
path = os.path.join(OUTPUT_DIR, "priced_traffic_economics.csv")
if os.path.isfile(path):
    result["priced_econ_exists"] = True
    content = safe_read(path)
    result["priced_econ_content"] = content
    result["priced_econ_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check CBA report CSV
path = os.path.join(OUTPUT_DIR, "congestion_pricing_cba.csv")
if os.path.isfile(path):
    result["cba_exists"] = True
    content = safe_read(path)
    result["cba_content"] = content
    result["cba_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check policy brief
path = os.path.join(OUTPUT_DIR, "congestion_pricing_brief.txt")
if os.path.isfile(path):
    result["brief_exists"] = True
    content = safe_read(path)
    result["brief_content"] = content
    result["brief_length"] = len(content)

with open(RESULT_PATH, "w") as f:
    json.dump(result, f, indent=2)

os.chmod(RESULT_PATH, 0o666)
print(json.dumps(result, indent=2))
PYEOF

echo "Result saved to /tmp/congestion_pricing_scenario_result.json"
echo "=== Export complete ==="
