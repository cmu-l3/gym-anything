#!/bin/bash
echo "=== Setting up optimize_network_signal_timing task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing SUMO processes
kill_sumo
sleep 1

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

# ──────────────────────────────────────────────
# Clean stale outputs BEFORE recording timestamp
# ──────────────────────────────────────────────
rm -f "${OUTPUT_DIR}/intersection_optimization_report.csv" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/baseline_metrics.csv" 2>/dev/null || true
rm -f "${WORK_DIR}/pasubio_tls_optimized.add.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/run_optimized.sumocfg" 2>/dev/null || true
rm -f "${WORK_DIR}"/tripinfo*.xml 2>/dev/null || true
rm -f "${WORK_DIR}"/tripinfos*.xml 2>/dev/null || true
rm -f "${WORK_DIR}"/edgedata*.xml 2>/dev/null || true
rm -f "${WORK_DIR}"/statistic*.xml 2>/dev/null || true
rm -f "${OUTPUT_DIR}"/tripinfo*.xml 2>/dev/null || true
rm -f "${OUTPUT_DIR}"/tripinfos*.xml 2>/dev/null || true
rm -f "${OUTPUT_DIR}"/edgedata*.xml 2>/dev/null || true
rm -f "${OUTPUT_DIR}"/statistic*.xml 2>/dev/null || true
rm -f /tmp/optimize_signal_* 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/optimize_signal_start_ts

# Ensure directories exist
mkdir -p "${OUTPUT_DIR}"
chown ga:ga "${OUTPUT_DIR}"
mkdir -p "${WORK_DIR}"

# ──────────────────────────────────────────────
# Restore clean Pasubio scenario from read-only mount
# ──────────────────────────────────────────────
cp /workspace/data/bologna_pasubio/pasubio_buslanes.net.xml "${WORK_DIR}/pasubio_buslanes.net.xml"
cp /workspace/data/bologna_pasubio/pasubio.rou.xml "${WORK_DIR}/pasubio.rou.xml"
cp /workspace/data/bologna_pasubio/pasubio_busses.rou.xml "${WORK_DIR}/pasubio_busses.rou.xml"
cp /workspace/data/bologna_pasubio/pasubio_tls.add.xml "${WORK_DIR}/pasubio_tls_original.add.xml"
cp /workspace/data/bologna_pasubio/pasubio_vtypes.add.xml "${WORK_DIR}/pasubio_vtypes.add.xml"
cp /workspace/data/bologna_pasubio/pasubio_detectors.add.xml "${WORK_DIR}/pasubio_detectors.add.xml"
cp /workspace/data/bologna_pasubio/pasubio_bus_stops.add.xml "${WORK_DIR}/pasubio_bus_stops.add.xml"
cp /workspace/data/bologna_pasubio/run.sumocfg "${WORK_DIR}/run.sumocfg" 2>/dev/null || true
# Remove any stale simulation output that came with the data directory
rm -f "${WORK_DIR}"/tripinfo*.xml "${WORK_DIR}"/tripinfos*.xml 2>/dev/null || true
rm -f "${WORK_DIR}"/edgedata*.xml "${WORK_DIR}"/statistic*.xml 2>/dev/null || true
rm -f "${WORK_DIR}"/summary.xml "${WORK_DIR}"/e1_output.xml 2>/dev/null || true
rm -f "${WORK_DIR}"/sumo_log.txt 2>/dev/null || true
chown -R ga:ga "${WORK_DIR}"

# ──────────────────────────────────────────────
# Generate suboptimal (equal-green-split) TLS file
# and run baseline simulation, compute ground truth
# ──────────────────────────────────────────────
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
import os
import sys
import copy

WORK_DIR = "/home/ga/SUMO_Scenarios/bologna_pasubio"
SUMO_HOME = os.environ.get("SUMO_HOME", "/usr/share/sumo")
sys.path.insert(0, os.path.join(SUMO_HOME, "tools"))

# ── Step 1: Generate equal-green-split (suboptimal) TLS file ──

original_tls_path = os.path.join(WORK_DIR, "pasubio_tls_original.add.xml")
suboptimal_tls_path = os.path.join(WORK_DIR, "pasubio_tls_suboptimal.add.xml")

tree = ET.parse(original_tls_path)
root = tree.getroot()

original_durations = {}  # tls_id -> list of original durations
suboptimal_durations = {}  # tls_id -> list of equal-split durations

for tl in root.findall("tlLogic"):
    tls_id = tl.get("id")
    phases = tl.findall("phase")
    orig_durs = [int(p.get("duration")) for p in phases]
    original_durations[tls_id] = orig_durs

    # Classify phases: "green" if duration > 6 AND state contains 'G' or 'g'
    green_indices = []
    for i, phase in enumerate(phases):
        dur = int(phase.get("duration"))
        state = phase.get("state", "")
        has_green = ("G" in state) or ("g" in state)
        if dur > 6 and has_green:
            green_indices.append(i)

    if not green_indices:
        suboptimal_durations[tls_id] = orig_durs
        continue

    # Compute total green time and distribute equally
    total_green = sum(int(phases[i].get("duration")) for i in green_indices)
    n_green = len(green_indices)
    base_dur = total_green // n_green
    remainder = total_green - base_dur * n_green

    new_durs = list(orig_durs)
    for j, idx in enumerate(green_indices):
        new_dur = base_dur + (1 if j < remainder else 0)
        new_durs[idx] = new_dur
        phases[idx].set("duration", str(new_dur))
        # Update minDur/maxDur to match so SUMO treats them as fixed-time
        if phases[idx].get("minDur") is not None:
            phases[idx].set("minDur", str(new_dur))
        if phases[idx].get("maxDur") is not None:
            phases[idx].set("maxDur", str(new_dur))

    suboptimal_durations[tls_id] = new_durs

tree.write(suboptimal_tls_path, xml_declaration=False)
print(f"Suboptimal TLS written to {suboptimal_tls_path}")

# Also make this the active TLS file for the baseline
import shutil
active_tls_path = os.path.join(WORK_DIR, "pasubio_tls.add.xml")
shutil.copy2(suboptimal_tls_path, active_tls_path)

# ── Step 2: Create baseline simulation config ──

# Write an edge-data collection additional file
edgedata_add_path = os.path.join(WORK_DIR, "edgedata_collect.add.xml")
with open(edgedata_add_path, "w") as f:
    f.write('<additional>\n')
    f.write('    <edgeData id="baseline_perf" freq="300" file="edgedata_baseline.xml"/>\n')
    f.write('</additional>\n')

# Create the baseline run config
baseline_cfg_path = os.path.join(WORK_DIR, "run_baseline.sumocfg")
with open(baseline_cfg_path, "w") as f:
    f.write("""<configuration>
    <input>
        <net-file value="pasubio_buslanes.net.xml"/>
        <route-files value="pasubio.rou.xml,pasubio_busses.rou.xml"/>
        <additional-files value="pasubio_vtypes.add.xml,pasubio_tls.add.xml,pasubio_detectors.add.xml,pasubio_bus_stops.add.xml,edgedata_collect.add.xml"/>
    </input>
    <output>
        <tripinfo-output value="tripinfo_baseline.xml"/>
        <statistic-output value="statistics_baseline.xml"/>
    </output>
    <processing>
        <no-step-log value="true"/>
    </processing>
    <random_number>
        <seed value="42"/>
    </random_number>
</configuration>
""")

# Also update the main run.sumocfg to reference the suboptimal TLS
# (this is what the agent will see as the "current" config)
main_cfg_path = os.path.join(WORK_DIR, "run.sumocfg")
with open(main_cfg_path, "w") as f:
    f.write("""<configuration>
    <input>
        <net-file value="pasubio_buslanes.net.xml"/>
        <route-files value="pasubio.rou.xml,pasubio_busses.rou.xml"/>
        <additional-files value="pasubio_vtypes.add.xml,pasubio_tls.add.xml,pasubio_detectors.add.xml,pasubio_bus_stops.add.xml"/>
    </input>
    <random_number>
        <seed value="42"/>
    </random_number>
</configuration>
""")

# Set ownership
for fname in [suboptimal_tls_path, active_tls_path, edgedata_add_path,
              baseline_cfg_path, main_cfg_path]:
    os.chmod(fname, 0o664)

# Save initial data for later use
initial_data = {
    "original_durations": original_durations,
    "suboptimal_durations": suboptimal_durations,
}
with open("/tmp/optimize_signal_initial_data.json", "w") as f:
    json.dump(initial_data, f, indent=2)

print("Setup phase 1 complete: configs and suboptimal TLS generated.")
PYEOF

chown -R ga:ga "${WORK_DIR}"

# ──────────────────────────────────────────────
# Run baseline simulation headlessly
# ──────────────────────────────────────────────
echo "Running baseline simulation (headless, ~60 seconds)..."
su - ga -c "cd ${WORK_DIR} && SUMO_HOME=/usr/share/sumo sumo -c run_baseline.sumocfg --no-step-log true --duration-log.statistics true > /tmp/baseline_sim.log 2>&1" || true

if [ -f "${WORK_DIR}/edgedata_baseline.xml" ]; then
    echo "Baseline edgedata generated successfully."
else
    echo "Warning: Baseline edgedata not generated."
fi

# ──────────────────────────────────────────────
# Compute ground truth: per-junction delay and 3 worst intersections
# ──────────────────────────────────────────────
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
import os
import sys

WORK_DIR = "/home/ga/SUMO_Scenarios/bologna_pasubio"
SUMO_HOME = os.environ.get("SUMO_HOME", "/usr/share/sumo")
sys.path.insert(0, os.path.join(SUMO_HOME, "tools"))

TLS_IDS = ["218", "219", "220", "230", "231", "232", "233", "282"]

ground_truth = {
    "computed": False,
    "junction_delay": {},
    "worst_3": [],
    "junction_approach_edges": {},
    "junction_approach_volumes": {},
    "network_metrics": {}
}

try:
    import sumolib

    # Load network
    net = sumolib.net.readNet(os.path.join(WORK_DIR, "pasubio_buslanes.net.xml"))

    # Get incoming (non-internal) edges for each TLS via getConnections()
    # Note: TLS IDs don't match node IDs in this network, so we use TLS objects
    junction_edges = {}
    for tls_id in TLS_IDS:
        try:
            tls = net.getTLS(tls_id)
            incoming = set()
            for conn in tls.getConnections():
                edge_id = conn[0].getEdge().getID()
                if not edge_id.startswith(":"):
                    incoming.add(edge_id)
            junction_edges[tls_id] = sorted(incoming)
        except Exception:
            junction_edges[tls_id] = []

    ground_truth["junction_approach_edges"] = junction_edges

    # Compute free-flow travel times per edge
    edge_freeflow = {}
    for tls_id, edges in junction_edges.items():
        for eid in edges:
            try:
                edge = net.getEdge(eid)
                length = edge.getLength()
                speed = edge.getSpeed()
                if speed > 0:
                    edge_freeflow[eid] = length / speed
            except Exception:
                pass

    # Parse edge data output
    edgedata_path = os.path.join(WORK_DIR, "edgedata_baseline.xml")
    if os.path.isfile(edgedata_path):
        tree = ET.parse(edgedata_path)
        root = tree.getroot()

        edge_traveltime = {}
        edge_entered = {}
        for interval in root.findall("interval"):
            for edge_el in interval.findall("edge"):
                eid = edge_el.get("id")
                tt_str = edge_el.get("traveltime")
                entered_str = edge_el.get("entered")
                if tt_str and eid:
                    tt = float(tt_str)
                    entered = int(float(entered_str)) if entered_str else 0
                    if eid not in edge_traveltime:
                        edge_traveltime[eid] = []
                        edge_entered[eid] = []
                    edge_traveltime[eid].append(tt)
                    edge_entered[eid].append(entered)

        # Average traveltime per edge (weighted across intervals not needed;
        # just simple average since intervals are equal-length)
        edge_avg_tt = {}
        edge_total_entered = {}
        for eid in edge_traveltime:
            edge_avg_tt[eid] = sum(edge_traveltime[eid]) / len(edge_traveltime[eid])
            edge_total_entered[eid] = sum(edge_entered[eid])

        # Compute per-junction weighted-average delay
        junction_delay = {}
        for tls_id, edges in junction_edges.items():
            total_delay_veh = 0.0
            total_vehicles = 0
            for eid in edges:
                if eid in edge_avg_tt and eid in edge_freeflow:
                    delay = max(0.0, edge_avg_tt[eid] - edge_freeflow[eid])
                    vehicles = edge_total_entered.get(eid, 0)
                    total_delay_veh += delay * vehicles
                    total_vehicles += vehicles
            if total_vehicles > 0:
                junction_delay[tls_id] = round(total_delay_veh / total_vehicles, 2)
            else:
                junction_delay[tls_id] = 0.0

        ground_truth["junction_delay"] = junction_delay

        # Sort by delay descending, pick worst 3
        sorted_j = sorted(junction_delay.items(), key=lambda x: x[1], reverse=True)
        ground_truth["worst_3"] = [j[0] for j in sorted_j[:3]]
        ground_truth["computed"] = True

        print(f"Per-junction delays: {junction_delay}")
        print(f"Worst 3 junctions: {ground_truth['worst_3']}")

    # Parse route files for per-approach demand volumes
    route_path = os.path.join(WORK_DIR, "pasubio.rou.xml")
    bus_route_path = os.path.join(WORK_DIR, "pasubio_busses.rou.xml")

    edge_vehicle_count = {}
    for rp in [route_path, bus_route_path]:
        if os.path.isfile(rp):
            rtree = ET.parse(rp)
            rroot = rtree.getroot()
            for vehicle in rroot.findall("vehicle"):
                route_el = vehicle.find("route")
                if route_el is not None:
                    edges = route_el.get("edges", "").split()
                    for eid in edges:
                        edge_vehicle_count[eid] = edge_vehicle_count.get(eid, 0) + 1

    junction_approach_volumes = {}
    for tls_id, edges in junction_edges.items():
        volumes = {}
        for eid in edges:
            volumes[eid] = edge_vehicle_count.get(eid, 0)
        junction_approach_volumes[tls_id] = volumes

    ground_truth["junction_approach_volumes"] = junction_approach_volumes

    # Parse baseline statistics for network-wide metrics
    stats_path = os.path.join(WORK_DIR, "statistics_baseline.xml")
    if os.path.isfile(stats_path):
        stree = ET.parse(stats_path)
        sroot = stree.getroot()
        veh_stats = sroot.find(".//vehicleTripStatistics")
        if veh_stats is not None:
            ground_truth["network_metrics"] = {
                "count": veh_stats.get("count", ""),
                "routeLength": veh_stats.get("routeLength", ""),
                "speed": veh_stats.get("speed", ""),
                "duration": veh_stats.get("duration", ""),
                "waitingTime": veh_stats.get("waitingTime", ""),
                "timeLoss": veh_stats.get("timeLoss", ""),
                "totalTravelTime": veh_stats.get("totalTravelTime", ""),
            }
            print(f"Network metrics: {ground_truth['network_metrics']}")

except Exception as e:
    ground_truth["error"] = str(e)
    import traceback
    traceback.print_exc()

with open("/tmp/optimize_signal_ground_truth.json", "w") as f:
    json.dump(ground_truth, f, indent=2)
os.chmod("/tmp/optimize_signal_ground_truth.json", 0o666)

# Also merge with initial data
try:
    with open("/tmp/optimize_signal_initial_data.json") as f:
        initial_data = json.load(f)
    initial_data["ground_truth"] = ground_truth
    with open("/tmp/optimize_signal_initial_data.json", "w") as f:
        json.dump(initial_data, f, indent=2)
    os.chmod("/tmp/optimize_signal_initial_data.json", 0o666)
except Exception:
    pass

print("Ground truth computation complete.")
PYEOF

chown -R ga:ga "${WORK_DIR}"

# ──────────────────────────────────────────────
# Open a terminal for the agent
# ──────────────────────────────────────────────
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'SUMO Signal Optimization Terminal' -e bash &" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Optimize signal timing for Bologna Pasubio (equal-split baseline)."
echo "Scenario: ${WORK_DIR}"
echo "Output report: ${OUTPUT_DIR}/intersection_optimization_report.csv"
