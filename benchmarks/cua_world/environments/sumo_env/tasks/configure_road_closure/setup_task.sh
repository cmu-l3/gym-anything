#!/bin/bash
set -e
echo "=== Setting up road closure task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running SUMO processes
kill_sumo || true

export SUMO_HOME="/usr/share/sumo"
export DISPLAY=:1

SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Ensure output directory exists and is clean
rm -f "$OUTPUT_DIR/closure_report.txt"
rm -f "$SCENARIO_DIR/road_closure.add.xml"
rm -f "$SCENARIO_DIR/closure_run.sumocfg"
rm -f "$SCENARIO_DIR/closure_tripinfo.xml"

mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Run Python script to select target edge and run baseline
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import os
import subprocess
import sys

scenario_dir = "/home/ga/SUMO_Scenarios/bologna_acosta"
sumocfg_path = os.path.join(scenario_dir, "run.sumocfg")

if not os.path.exists(sumocfg_path):
    print(f"ERROR: sumocfg not found at {sumocfg_path}")
    sys.exit(1)

# Parse sumocfg to find network and route files
tree = ET.parse(sumocfg_path)
root = tree.getroot()

net_file = None
route_files = []

for inp in root.iter('input'):
    nf = inp.find('net-file')
    if nf is not None:
        net_file = nf.get('value')
    rf = inp.find('route-files')
    if rf is not None:
        route_files = [f.strip() for f in rf.get('value').split(',')]

if not net_file:
    print("ERROR: Could not find net-file in sumocfg")
    sys.exit(1)

# Parse network to get non-internal edge IDs
net_path = os.path.join(scenario_dir, net_file)
net_tree = ET.parse(net_path)
net_root = net_tree.getroot()

all_edges = []
for edge in net_root.findall('edge'):
    edge_id = edge.get('id')
    if edge_id and not edge_id.startswith(':'):
        # Get number of lanes
        lanes = edge.findall('lane')
        if len(lanes) >= 1:
            all_edges.append(edge_id)

# Parse routes to find which edges are actually used
edge_usage = {}
for rf in route_files:
    rf_path = os.path.join(scenario_dir, rf)
    if not os.path.exists(rf_path):
        continue
    try:
        rt_tree = ET.parse(rf_path)
        rt_root = rt_tree.getroot()
        for route in rt_root.iter('route'):
            edges_str = route.get('edges', '')
            for e in edges_str.split():
                edge_usage[e] = edge_usage.get(e, 0) + 1
        # Also check vehicle elements with route children
        for vehicle in rt_root.iter('vehicle'):
            vr = vehicle.find('route')
            if vr is not None:
                edges_str = vr.get('edges', '')
                for e in edges_str.split():
                    edge_usage[e] = edge_usage.get(e, 0) + 1
    except Exception as ex:
        pass

if not edge_usage:
    target_edge = all_edges[len(all_edges) // 3]
else:
    # Select an edge that is moderately used (not the most used, not least)
    sorted_edges = sorted(edge_usage.items(), key=lambda x: x[1], reverse=True)
    idx = max(1, len(sorted_edges) // 4)
    target_edge = sorted_edges[idx][0]

# Verify the edge exists in the network
if target_edge not in all_edges:
    for e in all_edges:
        if target_edge in e or e in target_edge:
            target_edge = e
            break
    else:
        target_edge = all_edges[len(all_edges) // 3]

# Get edge details from network
edge_info = ""
for edge in net_root.findall('edge'):
    if edge.get('id') == target_edge:
        lanes = edge.findall('lane')
        edge_info = f"Lanes: {len(lanes)}"
        if lanes:
            speed = lanes[0].get('speed', 'unknown')
            length = lanes[0].get('length', 'unknown')
            edge_info += f", Speed limit: {speed} m/s, Length: {length} m"
        edge_from = edge.get('from', 'unknown')
        edge_to = edge.get('to', 'unknown')
        edge_info += f", From junction: {edge_from}, To junction: {edge_to}"
        break

# Write target edge info
target_file = os.path.join(scenario_dir, "closure_target.txt")
with open(target_file, 'w') as f:
    f.write(f"Target Edge ID: {target_edge}\n")
    f.write(f"Edge Details: {edge_info}\n")
    f.write(f"\n")
    f.write(f"This edge must be closed using a SUMO rerouter.\n")
    f.write(f"Vehicles currently using this edge should be rerouted to alternative paths.\n")

# Write just the edge ID for verification
with open("/tmp/closure_target_edge.txt", 'w') as f:
    f.write(target_edge)

# Run baseline simulation
baseline_cfg = os.path.join(scenario_dir, "baseline_run.sumocfg")
cfg_tree = ET.parse(sumocfg_path)
cfg_root = cfg_tree.getroot()

# Ensure output section exists with tripinfo
output_elem = cfg_root.find('output')
if output_elem is None:
    output_elem = ET.SubElement(cfg_root, 'output')

tripinfo_elem = output_elem.find('tripinfo-output')
if tripinfo_elem is None:
    tripinfo_elem = ET.SubElement(output_elem, 'tripinfo-output')
tripinfo_elem.set('value', 'baseline_tripinfo.xml')

# Remove gui_only section for headless run
gui_only = cfg_root.find('gui_only')
if gui_only is not None:
    cfg_root.remove(gui_only)

cfg_tree.write(baseline_cfg, xml_declaration=True, encoding='UTF-8')

subprocess.run(
    ['sumo', '-c', baseline_cfg],
    cwd=scenario_dir,
    capture_output=True,
    text=True,
    timeout=300
)
PYEOF

# Set ownership
chown -R ga:ga "$SCENARIO_DIR"
chown -R ga:ga "$OUTPUT_DIR"
chmod -R 755 "$SCENARIO_DIR"
chmod 644 /tmp/closure_target_edge.txt
chmod 644 /tmp/task_start_time.txt

# Open a terminal for the agent
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -e 'cd /home/ga/SUMO_Scenarios/bologna_acosta && echo \"=== Road Closure Task ===\"  && echo \"\" && cat closure_target.txt && echo \"\" && echo \"Working directory: \$(pwd)\" && echo \"\" && bash' &"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Road closure task setup complete ==="