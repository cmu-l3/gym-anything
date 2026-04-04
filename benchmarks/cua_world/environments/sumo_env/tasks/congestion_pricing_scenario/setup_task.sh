#!/bin/bash
echo "=== Setting up congestion_pricing_scenario task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/congestion_pricing_scenario_start_ts

# Kill any existing SUMO processes
kill_sumo
sleep 1

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Clean up previous outputs
rm -f "${OUTPUT_DIR}/baseline_traffic_economics.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/priced_traffic_economics.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/congestion_pricing_cba.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/congestion_pricing_brief.txt" 2>/dev/null || true
rm -f "${WORK_DIR}/pasubio_priced.rou.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/run_priced.sumocfg" 2>/dev/null || true
rm -f "${WORK_DIR}/tripinfos.xml" 2>/dev/null || true
rm -f "${WORK_DIR}"/*priced* 2>/dev/null || true
rm -f "${WORK_DIR}"/*pricing* 2>/dev/null || true
rm -f "${WORK_DIR}/sumo_log.txt" 2>/dev/null || true
rm -f /tmp/congestion_pricing_scenario_* 2>/dev/null || true

# Re-record timestamp after cleanup
date +%s > /tmp/congestion_pricing_scenario_start_ts

# Ensure output directory
mkdir -p "${OUTPUT_DIR}"
chown ga:ga "${OUTPUT_DIR}"

# Restore clean scenario files
cp /workspace/data/bologna_pasubio/pasubio_buslanes.net.xml "${WORK_DIR}/pasubio_buslanes.net.xml"
cp /workspace/data/bologna_pasubio/pasubio.rou.xml "${WORK_DIR}/pasubio.rou.xml"
cp /workspace/data/bologna_pasubio/pasubio_busses.rou.xml "${WORK_DIR}/pasubio_busses.rou.xml"
cp /workspace/data/bologna_pasubio/pasubio_detectors.add.xml "${WORK_DIR}/pasubio_detectors.add.xml"
cp /workspace/data/bologna_pasubio/pasubio_bus_stops.add.xml "${WORK_DIR}/pasubio_bus_stops.add.xml"
cp /workspace/data/bologna_pasubio/pasubio_tls.add.xml "${WORK_DIR}/pasubio_tls.add.xml"
cp /workspace/data/bologna_pasubio/pasubio_vtypes.add.xml "${WORK_DIR}/pasubio_vtypes.add.xml"
cp /workspace/data/bologna_pasubio/run.sumocfg "${WORK_DIR}/run.sumocfg"
chown -R ga:ga "${WORK_DIR}"

# Record initial vehicle and route data for verifier
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
from collections import Counter

initial_data = {
    "private_vehicle_count": 0,
    "bus_vehicle_count": 0,
    "total_vehicle_count": 0,
    "vehicle_types": {},
    "edges": [],
    "edge_count": 0
}

# Count private vehicles
rou_file = "/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio.rou.xml"
try:
    tree = ET.parse(rou_file)
    root = tree.getroot()
    vehicles = root.findall('vehicle')
    initial_data["private_vehicle_count"] = len(vehicles)
    type_counts = Counter(v.get('type', '') for v in vehicles)
    initial_data["vehicle_types"] = dict(type_counts)
except Exception as e:
    initial_data["route_error"] = str(e)

# Count bus vehicles
bus_file = "/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_busses.rou.xml"
try:
    tree = ET.parse(bus_file)
    root = tree.getroot()
    initial_data["bus_vehicle_count"] = len(root.findall('vehicle'))
except Exception as e:
    initial_data["bus_error"] = str(e)

initial_data["total_vehicle_count"] = initial_data["private_vehicle_count"] + initial_data["bus_vehicle_count"]

# Get edges
net_file = "/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_buslanes.net.xml"
try:
    tree = ET.parse(net_file)
    root = tree.getroot()
    edges = [e.get('id', '') for e in root.findall('edge') if not e.get('id', '').startswith(':')]
    initial_data["edges"] = edges
    initial_data["edge_count"] = len(edges)
except Exception as e:
    initial_data["net_error"] = str(e)

with open("/tmp/congestion_pricing_scenario_initial_data.json", "w") as f:
    json.dump(initial_data, f, indent=2)
PYEOF

# Open a terminal
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'SUMO Congestion Pricing Terminal' -e bash &" 2>/dev/null || true
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Evaluate congestion pricing policy for Bologna Pasubio corridor."
echo "Scenario: ${WORK_DIR}/"
