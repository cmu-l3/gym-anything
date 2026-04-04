#!/bin/bash
echo "=== Setting up arterial_signal_coordination task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/arterial_signal_coordination_start_ts

# Kill any existing SUMO processes
kill_sumo
sleep 1

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Clean up previous outputs
rm -f "${OUTPUT_DIR}/baseline_corridor_metrics.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/coordinated_corridor_metrics.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/signal_coordination_report.txt" 2>/dev/null || true
rm -f "${WORK_DIR}/acosta_tls_coordinated.add.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/run_coordinated.sumocfg" 2>/dev/null || true
rm -f "${WORK_DIR}/tripinfos.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/tripinfos_coordinated.xml" 2>/dev/null || true
rm -f "${WORK_DIR}"/*coordinated* 2>/dev/null || true
rm -f "${WORK_DIR}/sumo_log.txt" 2>/dev/null || true
rm -f /tmp/arterial_signal_coordination_* 2>/dev/null || true

# Re-record timestamp after cleanup
date +%s > /tmp/arterial_signal_coordination_start_ts

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

# Record initial TLS data for verifier
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json

initial_data = {"tls_programs": {}, "tls_offsets": {}, "tls_cycle_lengths": {}}

tls_file = "/home/ga/SUMO_Scenarios/bologna_acosta/acosta_tls.add.xml"
try:
    tree = ET.parse(tls_file)
    root = tree.getroot()
    for tl in root.findall('tlLogic'):
        tid = tl.get('id', '')
        offset = tl.get('offset', '0')
        initial_data["tls_offsets"][tid] = int(offset)

        # Compute cycle length
        cycle = 0
        for phase in tl.findall('phase'):
            cycle += int(phase.get('duration', '0'))
        initial_data["tls_cycle_lengths"][tid] = cycle

        initial_data["tls_programs"][tid] = {
            "programID": tl.get('programID', ''),
            "type": tl.get('type', ''),
            "offset": int(offset),
            "cycle_length": cycle,
            "num_phases": len(tl.findall('phase'))
        }
except Exception as e:
    initial_data["error"] = str(e)

# Record junction positions for offset computation reference
net_file = "/home/ga/SUMO_Scenarios/bologna_acosta/acosta_buslanes.net.xml"
tls_ids = ["209", "210", "219", "220", "221", "235", "273"]
try:
    tree = ET.parse(net_file)
    root = tree.getroot()
    junction_positions = {}
    for j in root.findall('junction'):
        jid = j.get('id', '')
        if jid in tls_ids:
            junction_positions[jid] = {
                "x": float(j.get('x', '0')),
                "y": float(j.get('y', '0'))
            }
    initial_data["junction_positions"] = junction_positions
except Exception as e:
    initial_data["junction_error"] = str(e)

with open("/tmp/arterial_signal_coordination_initial_data.json", "w") as f:
    json.dump(initial_data, f, indent=2)
PYEOF

# Open a terminal
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'SUMO Signal Coordination Terminal' -e bash &" 2>/dev/null || true
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Implement green wave signal coordination on Bologna Acosta corridor."
echo "Scenario: ${WORK_DIR}/"
echo "TLS IDs to coordinate: 209, 210, 219, 220, 221, 235, 273"
