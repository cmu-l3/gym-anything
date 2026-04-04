#!/bin/bash
echo "=== Setting up incident_rerouting_evaluation task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/incident_rerouting_evaluation_start_ts

# Kill any existing SUMO processes
kill_sumo
sleep 1

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Clean up previous outputs
rm -f "${OUTPUT_DIR}/baseline_network_performance.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/incident_network_performance.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/incident_assessment_report.txt" 2>/dev/null || true
rm -f "${WORK_DIR}/incident_rerouters.add.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/run_incident.sumocfg" 2>/dev/null || true
rm -f "${WORK_DIR}/tripinfos.xml" 2>/dev/null || true
rm -f "${WORK_DIR}"/*incident* 2>/dev/null || true
rm -f "${WORK_DIR}/sumo_log.txt" 2>/dev/null || true
rm -f /tmp/incident_rerouting_evaluation_* 2>/dev/null || true

# Re-record timestamp after cleanup
date +%s > /tmp/incident_rerouting_evaluation_start_ts

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

# Record initial edge data for verifier
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json

initial_data = {"edges": [], "edge_count": 0, "edge_lanes": {}}

net_file = "/home/ga/SUMO_Scenarios/bologna_acosta/acosta_buslanes.net.xml"
try:
    tree = ET.parse(net_file)
    root = tree.getroot()
    for edge in root.findall('edge'):
        eid = edge.get('id', '')
        if eid.startswith(':'):
            continue
        initial_data["edges"].append(eid)
        lanes = [l.get('id', '') for l in edge.findall('lane')]
        initial_data["edge_lanes"][eid] = lanes
    initial_data["edge_count"] = len(initial_data["edges"])
except Exception as e:
    initial_data["error"] = str(e)

with open("/tmp/incident_rerouting_evaluation_initial_data.json", "w") as f:
    json.dump(initial_data, f, indent=2)
PYEOF

# Open a terminal
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'SUMO Incident Analysis Terminal' -e bash &" 2>/dev/null || true
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Evaluate network resilience to incident with dynamic rerouting."
echo "Scenario: ${WORK_DIR}/"
