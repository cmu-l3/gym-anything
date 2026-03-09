#!/bin/bash
echo "=== Setting up detector_demand_calibration task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/detector_demand_calibration_start_ts

# Kill any existing SUMO processes
kill_sumo
sleep 1

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Clean up previous outputs
rm -f "${OUTPUT_DIR}/baseline_detector_counts.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/observed_detector_counts.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/calibrated_detector_counts.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/calibration_report.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/calibration_summary.txt" 2>/dev/null || true
rm -f "${WORK_DIR}/acosta_calibrated.rou.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/run_calibrated.sumocfg" 2>/dev/null || true
rm -f "${WORK_DIR}/e1_output.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/tripinfos.xml" 2>/dev/null || true
rm -f "${WORK_DIR}"/*calibrat* 2>/dev/null || true
rm -f "${WORK_DIR}/sumo_log.txt" 2>/dev/null || true
rm -f /tmp/detector_demand_calibration_* 2>/dev/null || true

# Re-record timestamp after cleanup
date +%s > /tmp/detector_demand_calibration_start_ts

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

# Record initial detector configuration for verifier
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json

initial_data = {"detectors": [], "detector_count": 0, "vehicle_count": 0}

det_file = "/home/ga/SUMO_Scenarios/bologna_acosta/acosta_detectors.add.xml"
try:
    tree = ET.parse(det_file)
    root = tree.getroot()
    for det in root.findall('.//e1Detector'):
        initial_data["detectors"].append({
            "id": det.get('id', ''),
            "lane": det.get('lane', ''),
            "pos": det.get('pos', ''),
            "freq": det.get('freq', ''),
            "file": det.get('file', '')
        })
    initial_data["detector_count"] = len(initial_data["detectors"])
except Exception as e:
    initial_data["detector_error"] = str(e)

# Count vehicles in original route file
rou_file = "/home/ga/SUMO_Scenarios/bologna_acosta/acosta.rou.xml"
try:
    tree = ET.parse(rou_file)
    root = tree.getroot()
    initial_data["vehicle_count"] = len(root.findall('vehicle'))
except Exception as e:
    initial_data["route_error"] = str(e)

with open("/tmp/detector_demand_calibration_initial_data.json", "w") as f:
    json.dump(initial_data, f, indent=2)
PYEOF

# Open a terminal
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'SUMO Demand Calibration Terminal' -e bash &" 2>/dev/null || true
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Calibrate traffic demand against detector data on Bologna Acosta."
echo "Scenario: ${WORK_DIR}/"
echo "Detectors: 58 E1 detectors, freq=1800s, output=e1_output.xml"
