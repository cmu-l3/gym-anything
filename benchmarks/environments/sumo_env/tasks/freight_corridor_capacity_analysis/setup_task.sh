#!/bin/bash
echo "=== Setting up freight_corridor_capacity_analysis task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/freight_corridor_capacity_analysis_start_ts

# Kill any existing SUMO processes
kill_sumo
sleep 1

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Clean up any previous task outputs
rm -f "${OUTPUT_DIR}/corridor_capacity_report.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/corridor_recommendation.txt" 2>/dev/null || true
rm -f "${WORK_DIR}/tripinfos.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/sumo_log.txt" 2>/dev/null || true
rm -f "${WORK_DIR}/e1_output.xml" 2>/dev/null || true
rm -f /tmp/freight_corridor_*  2>/dev/null || true

# Ensure output directory exists
mkdir -p "${OUTPUT_DIR}"
chown ga:ga "${OUTPUT_DIR}"

# Ensure scenario files are in place (restore from read-only mount)
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

# Run the baseline simulation headless to produce baseline tripinfo
echo "Running baseline simulation (headless)..."
BASELINE_DIR="/home/ga/SUMO_Scenarios/bologna_acosta_baseline"
mkdir -p "${BASELINE_DIR}"
cp "${WORK_DIR}"/* "${BASELINE_DIR}/" 2>/dev/null || true
chown -R ga:ga "${BASELINE_DIR}"

su - ga -c "cd ${BASELINE_DIR} && SUMO_HOME=/usr/share/sumo sumo -c run.sumocfg --tripinfo-output tripinfos_baseline.xml --no-step-log true --duration-log.statistics true > /tmp/baseline_sim.log 2>&1" || true

# Copy baseline tripinfo to a known location for the agent to reference
if [ -f "${BASELINE_DIR}/tripinfos_baseline.xml" ]; then
    cp "${BASELINE_DIR}/tripinfos_baseline.xml" "${WORK_DIR}/tripinfos_baseline.xml"
    chown ga:ga "${WORK_DIR}/tripinfos_baseline.xml"
    echo "Baseline tripinfo available at ${WORK_DIR}/tripinfos_baseline.xml"
else
    echo "Warning: Baseline simulation did not produce tripinfo output"
fi

# Record baseline stats for verifier
BASELINE_STATS="/tmp/freight_corridor_baseline_stats.json"
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
import sys

baseline_file = "/home/ga/SUMO_Scenarios/bologna_acosta_baseline/tripinfos_baseline.xml"
stats = {"computed": False}

try:
    tree = ET.parse(baseline_file)
    root = tree.getroot()
    trips = root.findall('tripinfo')

    if len(trips) > 0:
        durations = [float(t.get('duration', 0)) for t in trips]
        speeds = []
        wait_times = []
        for t in trips:
            route_len = float(t.get('routeLength', 0))
            dur = float(t.get('duration', 1))
            if dur > 0 and route_len > 0:
                speeds.append(route_len / dur)
            wait_times.append(float(t.get('waitingTime', 0)))

        stats = {
            "computed": True,
            "avg_travel_time": sum(durations) / len(durations),
            "avg_speed": sum(speeds) / len(speeds) if speeds else 0,
            "total_vehicles_completed": len(trips),
            "avg_waiting_time": sum(wait_times) / len(wait_times)
        }
except Exception as e:
    stats["error"] = str(e)

with open("/tmp/freight_corridor_baseline_stats.json", "w") as f:
    json.dump(stats, f, indent=2)
PYEOF

chown ga:ga "${BASELINE_STATS}" 2>/dev/null || true

# Open a terminal for the agent
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'SUMO Freight Analysis Terminal' -e bash &" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Create freight capacity analysis for Bologna Acosta corridor."
echo "Baseline tripinfo: ${WORK_DIR}/tripinfos_baseline.xml"
echo "Output CSV: ${OUTPUT_DIR}/corridor_capacity_report.csv"
echo "Output recommendation: ${OUTPUT_DIR}/corridor_recommendation.txt"
