#!/bin/bash
echo "=== Setting up intersection_safety_audit task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/intersection_safety_audit_start_ts

# Kill any existing SUMO processes
kill_sumo
sleep 1

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Clean up previous task outputs
rm -f "${OUTPUT_DIR}/ssm_output.xml" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/intersection_safety_report.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/safety_audit_summary.txt" 2>/dev/null || true
rm -f "${WORK_DIR}/tripinfos.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/sumo_log.txt" 2>/dev/null || true
rm -f "${WORK_DIR}/e1_output.xml" 2>/dev/null || true
rm -f /tmp/intersection_safety_* 2>/dev/null || true

# Ensure output directory exists
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

# Pre-compute junction info for verifier reference
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json

net_file = "/home/ga/SUMO_Scenarios/bologna_acosta/acosta_buslanes.net.xml"
junctions = {}

try:
    tree = ET.parse(net_file)
    root = tree.getroot()
    for junc in root.findall('junction'):
        jid = junc.get('id', '')
        jtype = junc.get('type', '')
        if jtype == 'traffic_light':
            junctions[jid] = {
                "type": jtype,
                "x": float(junc.get('x', 0)),
                "y": float(junc.get('y', 0))
            }
except Exception as e:
    junctions["error"] = str(e)

with open("/tmp/intersection_safety_junction_info.json", "w") as f:
    json.dump(junctions, f, indent=2)
PYEOF

# Open a terminal for the agent
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'SUMO Safety Audit Terminal' -e bash &" 2>/dev/null || true
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Configure SSM device, run simulation, produce intersection safety audit report."
echo "Scenario: ${WORK_DIR}/run.sumocfg"
echo "Report: ${OUTPUT_DIR}/intersection_safety_report.csv"
echo "Summary: ${OUTPUT_DIR}/safety_audit_summary.txt"
