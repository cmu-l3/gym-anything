#!/bin/bash
echo "=== Setting up emission_zone_impact_study task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/emission_zone_impact_study_start_ts

# Kill any existing SUMO processes
kill_sumo
sleep 1

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Clean up previous outputs
rm -f "${OUTPUT_DIR}/baseline_emissions.xml" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/lez_emissions.xml" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/emission_impact_report.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/emission_impact_summary.txt" 2>/dev/null || true
rm -f "${WORK_DIR}/tripinfos.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/sumo_log.txt" 2>/dev/null || true
rm -f "${WORK_DIR}"/*emission*.xml 2>/dev/null || true
rm -f "${WORK_DIR}"/*lez*.xml 2>/dev/null || true
rm -f /tmp/emission_zone_* 2>/dev/null || true

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

# Record initial emission classes and edge count for verifier
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json

# Record vehicle type emission classes
vtypes_file = "/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_vtypes.add.xml"
emission_data = {"emission_classes": {}, "edge_count": 0, "edge_ids": []}

try:
    tree = ET.parse(vtypes_file)
    root = tree.getroot()
    for vtype in root.iter('vType'):
        vid = vtype.get('id', '')
        eclass = vtype.get('emissionClass', '')
        if eclass:
            emission_data["emission_classes"][vid] = eclass
except Exception as e:
    emission_data["vtypes_error"] = str(e)

# Record edges
net_file = "/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_buslanes.net.xml"
try:
    tree = ET.parse(net_file)
    root = tree.getroot()
    edges = [e.get('id', '') for e in root.findall('edge') if not e.get('id', '').startswith(':')]
    emission_data["edge_count"] = len(edges)
    emission_data["edge_ids"] = edges[:50]  # first 50 for reference
except Exception as e:
    emission_data["net_error"] = str(e)

with open("/tmp/emission_zone_initial_data.json", "w") as f:
    json.dump(emission_data, f, indent=2)
PYEOF

# Open a terminal
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'SUMO Emission Study Terminal' -e bash &" 2>/dev/null || true
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Conduct emission impact study for Low Emission Zone in Bologna Pasubio."
echo "Scenario: ${WORK_DIR}/"
echo "Report: ${OUTPUT_DIR}/emission_impact_report.csv"
echo "Summary: ${OUTPUT_DIR}/emission_impact_summary.txt"
