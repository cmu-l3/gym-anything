#!/bin/bash
echo "=== Setting up multimodal_person_trip_analysis task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/multimodal_person_trip_analysis_start_ts

# Kill any existing SUMO processes
kill_sumo
sleep 1

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Clean up previous outputs
rm -f "${OUTPUT_DIR}/modal_performance.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/bus_stop_analysis.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/underserved_stops.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/transit_assessment_report.txt" 2>/dev/null || true
rm -f "${WORK_DIR}/acosta_new_bus_route.rou.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/run_improved_transit.sumocfg" 2>/dev/null || true
rm -f "${WORK_DIR}/stop_output.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/tripinfos.xml" 2>/dev/null || true
rm -f "${WORK_DIR}"/*improved* 2>/dev/null || true
rm -f "${WORK_DIR}"/*new_bus* 2>/dev/null || true
rm -f "${WORK_DIR}/sumo_log.txt" 2>/dev/null || true
rm -f /tmp/multimodal_person_trip_analysis_* 2>/dev/null || true

# Re-record timestamp after cleanup
date +%s > /tmp/multimodal_person_trip_analysis_start_ts

# Ensure output directory
mkdir -p "${OUTPUT_DIR}"
chown ga:ga "${OUTPUT_DIR}"

# Restore clean scenario files
cp /workspace/data/bologna_acosta/acosta_buslanes.net.xml "${WORK_DIR}/acosta_buslanes.net.xml"
cp /workspace/data/bologna_acosta/acosta.rou.xml "${WORK_DIR}/acosta.rou.xml"
cp /workspace/data/bologna_acosta/acosta_busses.rou.xml "${WORK_DIR}/acosta_busses.rou.xml"
cp /workspace/data/bologna_acosta/acosta_detectors.add.xml "${WORK_DIR}/acosta_detectors.add.xml"
cp /workspace/data/bologna_acosta/acosta_bus_stops.add.xml "${WORK_DIR}/acosta_bus_stops.add.xml"
cp /workspace/data/bologna_acosta/acosta_tls.add.xml "${WORK_DIR}/acosta_tls.add.xml"
cp /workspace/data/bologna_acosta/acosta_vtypes.add.xml "${WORK_DIR}/acosta_vtypes.add.xml"
cp /workspace/data/bologna_acosta/run.sumocfg "${WORK_DIR}/run.sumocfg"
cp /workspace/data/bologna_acosta/settings.gui.xml "${WORK_DIR}/settings.gui.xml" 2>/dev/null || true
chown -R ga:ga "${WORK_DIR}"

# Record initial bus stop and route data for verifier
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json

initial_data = {"bus_stops": [], "bus_stop_count": 0, "bus_vehicle_count": 0, "bus_routes": {}}

# Parse bus stops
stop_file = "/home/ga/SUMO_Scenarios/bologna_acosta/acosta_bus_stops.add.xml"
try:
    tree = ET.parse(stop_file)
    root = tree.getroot()
    for stop in root.findall('busStop'):
        initial_data["bus_stops"].append({
            "id": stop.get('id', ''),
            "lane": stop.get('lane', ''),
            "startPos": stop.get('startPos', ''),
            "endPos": stop.get('endPos', '')
        })
    initial_data["bus_stop_count"] = len(initial_data["bus_stops"])
except Exception as e:
    initial_data["stop_error"] = str(e)

# Parse bus routes
bus_rou_file = "/home/ga/SUMO_Scenarios/bologna_acosta/acosta_busses.rou.xml"
try:
    tree = ET.parse(bus_rou_file)
    root = tree.getroot()
    vehicles = root.findall('vehicle')
    initial_data["bus_vehicle_count"] = len(vehicles)
    for v in vehicles[:10]:  # Sample
        vid = v.get('id', '')
        stops = [s.get('busStop', '') for s in v.findall('stop')]
        initial_data["bus_routes"][vid] = stops
except Exception as e:
    initial_data["route_error"] = str(e)

with open("/tmp/multimodal_person_trip_analysis_initial_data.json", "w") as f:
    json.dump(initial_data, f, indent=2)
PYEOF

# Open a terminal
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'SUMO Transit Analysis Terminal' -e bash &" 2>/dev/null || true
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Analyze multimodal transit accessibility on Bologna Acosta corridor."
echo "Scenario: ${WORK_DIR}/"
echo "Bus stops: 35, Bus vehicles: 157"
