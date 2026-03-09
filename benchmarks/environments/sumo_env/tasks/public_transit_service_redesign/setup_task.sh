#!/bin/bash
echo "=== Setting up public_transit_service_redesign task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/public_transit_service_redesign_start_ts

# Kill any existing SUMO processes
kill_sumo
sleep 1

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Clean up previous outputs
rm -f "${OUTPUT_DIR}/transit_service_report.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/transit_redesign_summary.txt" 2>/dev/null || true
rm -f "${WORK_DIR}/tripinfos.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/sumo_log.txt" 2>/dev/null || true
rm -f "${WORK_DIR}"/new_*.xml 2>/dev/null || true
rm -f "${WORK_DIR}"/express_*.xml 2>/dev/null || true
rm -f "${WORK_DIR}"/persons*.xml 2>/dev/null || true
rm -f "${WORK_DIR}"/person_*.xml 2>/dev/null || true
rm -f /tmp/public_transit_* 2>/dev/null || true

# Ensure output directory
mkdir -p "${OUTPUT_DIR}"
chown ga:ga "${OUTPUT_DIR}"

# Restore clean scenario files
cp /workspace/data/bologna_pasubio/pasubio.rou.xml "${WORK_DIR}/pasubio.rou.xml"
cp /workspace/data/bologna_pasubio/pasubio_buslanes.net.xml "${WORK_DIR}/pasubio_buslanes.net.xml"
cp /workspace/data/bologna_pasubio/pasubio_bus_stops.add.xml "${WORK_DIR}/pasubio_bus_stops.add.xml"
cp /workspace/data/bologna_pasubio/pasubio_busses.rou.xml "${WORK_DIR}/pasubio_busses.rou.xml"
cp /workspace/data/bologna_pasubio/pasubio_detectors.add.xml "${WORK_DIR}/pasubio_detectors.add.xml"
cp /workspace/data/bologna_pasubio/pasubio_tls.add.xml "${WORK_DIR}/pasubio_tls.add.xml"
cp /workspace/data/bologna_pasubio/pasubio_vtypes.add.xml "${WORK_DIR}/pasubio_vtypes.add.xml"
chown -R ga:ga "${WORK_DIR}"

# Record initial bus stop count for verifier
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json

stops_file = "/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_bus_stops.add.xml"
bus_routes_file = "/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_busses.rou.xml"
initial_data = {"initial_stop_count": 0, "initial_stop_ids": [], "initial_bus_count": 0}

try:
    tree = ET.parse(stops_file)
    root = tree.getroot()
    stops = root.findall('busStop')
    initial_data["initial_stop_count"] = len(stops)
    initial_data["initial_stop_ids"] = [s.get('id', '') for s in stops]
except Exception as e:
    initial_data["stops_error"] = str(e)

try:
    tree = ET.parse(bus_routes_file)
    root = tree.getroot()
    buses = root.findall('vehicle')
    initial_data["initial_bus_count"] = len(buses)
except Exception as e:
    initial_data["bus_error"] = str(e)

with open("/tmp/public_transit_initial_data.json", "w") as f:
    json.dump(initial_data, f, indent=2)
PYEOF

# Open a terminal
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'SUMO Transit Planning Terminal' -e bash &" 2>/dev/null || true
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Redesign bus service in Bologna Pasubio network."
echo "Scenario: ${WORK_DIR}/"
echo "Report: ${OUTPUT_DIR}/transit_service_report.csv"
echo "Summary: ${OUTPUT_DIR}/transit_redesign_summary.txt"
