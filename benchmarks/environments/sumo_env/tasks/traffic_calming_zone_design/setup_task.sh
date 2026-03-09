#!/bin/bash
echo "=== Setting up traffic_calming_zone_design task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/traffic_calming_zone_design_start_ts

# Kill any existing SUMO processes
kill_sumo
sleep 1

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Clean up previous outputs
rm -f "${OUTPUT_DIR}/baseline_tripinfos.xml" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/calming_tripinfos.xml" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/traffic_calming_report.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/traffic_calming_summary.txt" 2>/dev/null || true
rm -f "${WORK_DIR}/tripinfos.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/sumo_log.txt" 2>/dev/null || true
rm -f "${WORK_DIR}/e1_output.xml" 2>/dev/null || true
rm -f /tmp/traffic_calming_* 2>/dev/null || true

# Ensure output directory
mkdir -p "${OUTPUT_DIR}"
chown ga:ga "${OUTPUT_DIR}"

# Restore clean scenario files
cp /workspace/data/bologna_acosta/acosta.rou.xml "${WORK_DIR}/acosta.rou.xml"
cp /workspace/data/bologna_acosta/acosta_buslanes.net.xml "${WORK_DIR}/acosta_buslanes.net.xml"
cp /workspace/data/bologna_acosta/acosta_vtypes.add.xml "${WORK_DIR}/acosta_vtypes.add.xml"
cp /workspace/data/bologna_acosta/acosta_detectors.add.xml "${WORK_DIR}/acosta_detectors.add.xml"
cp /workspace/data/bologna_acosta/acosta_bus_stops.add.xml "${WORK_DIR}/acosta_bus_stops.add.xml"
cp /workspace/data/bologna_acosta/acosta_busses.rou.xml "${WORK_DIR}/acosta_busses.rou.xml"
cp /workspace/data/bologna_acosta/acosta_tls.add.xml "${WORK_DIR}/acosta_tls.add.xml"
cp /workspace/data/bologna_acosta/run.sumocfg "${WORK_DIR}/run.sumocfg"
cp /workspace/data/bologna_acosta/settings.gui.xml "${WORK_DIR}/settings.gui.xml"
chown -R ga:ga "${WORK_DIR}"

# Pre-compute edge speed data for verifier reference
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json

net_file = "/home/ga/SUMO_Scenarios/bologna_acosta/acosta_buslanes.net.xml"
edge_data = {}

try:
    tree = ET.parse(net_file)
    root = tree.getroot()
    for edge in root.findall('edge'):
        eid = edge.get('id', '')
        if eid.startswith(':'):
            continue  # skip internal edges
        lanes = edge.findall('lane')
        speeds = [float(l.get('speed', 0)) for l in lanes]
        num_lanes = len(lanes)
        lengths = [float(l.get('length', 0)) for l in lanes]
        edge_data[eid] = {
            "num_lanes": num_lanes,
            "max_speed": max(speeds) if speeds else 0,
            "avg_length": sum(lengths) / len(lengths) if lengths else 0
        }
except Exception as e:
    edge_data["error"] = str(e)

with open("/tmp/traffic_calming_edge_data.json", "w") as f:
    json.dump(edge_data, f, indent=2)

# Count how many edges have speed <= 13.89 m/s (50 km/h) — likely residential
residential_count = sum(1 for v in edge_data.values()
                        if isinstance(v, dict) and v.get("max_speed", 999) <= 13.89
                        and v.get("num_lanes", 0) <= 2)
print(f"Potential residential edges (<=50km/h, <=2 lanes): {residential_count}")
print(f"Total non-internal edges: {len([k for k in edge_data if k != 'error'])}")
PYEOF

# Open a terminal
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'SUMO Traffic Calming Terminal' -e bash &" 2>/dev/null || true
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Design a 30 km/h traffic calming zone in Bologna Acosta residential area."
echo "Scenario: ${WORK_DIR}/"
echo "Report: ${OUTPUT_DIR}/traffic_calming_report.csv"
echo "Summary: ${OUTPUT_DIR}/traffic_calming_summary.txt"
