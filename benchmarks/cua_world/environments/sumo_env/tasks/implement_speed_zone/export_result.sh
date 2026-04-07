#!/bin/bash
echo "=== Exporting implement_speed_zone task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to parse files and evaluate metrics, saving to JSON
python3 << 'EOF'
import json
import os
import xml.etree.ElementTree as ET
import time

ZONA30_DIR = "/home/ga/SUMO_Scenarios/zona30"
OUTPUT_DIR = "/home/ga/SUMO_Output"

def read_float(path):
    try:
        with open(path, 'r') as f:
            return float(f.read().strip())
    except:
        return 0.0

result = {
    "task_start_time": read_float("/tmp/task_start_time.txt"),
    "baseline_avg_duration": read_float("/tmp/baseline_avg_duration.txt"),
    "expected_modified_edges": int(read_float("/tmp/expected_modified_edges.txt")),
    "plain_xml_exports": {},
    "modified_edge_file": {"exists": False, "valid": False, "edges_to_833": 0, "mtime": 0},
    "reimported_net": {"exists": False, "valid": False, "junctions": 0, "edges": 0},
    "sumo_config": {"exists": False, "valid": False, "has_net": False, "has_routes": False, "has_tripinfo": False},
    "simulation_output": {"exists": False, "valid": False, "trip_count": 0, "avg_duration": 0.0, "mtime": 0},
    "summary_file": {"exists": False, "content": ""}
}

# Check Plain XML
for ext in ['nod', 'edg', 'con', 'tll']:
    path = f"{ZONA30_DIR}/pasubio_plain.{ext}.xml"
    exists = os.path.exists(path)
    size = os.path.getsize(path) if exists else 0
    result["plain_xml_exports"][ext] = {"exists": exists, "size": size}

# Check Modified Edge File
mod_edg_path = f"{ZONA30_DIR}/pasubio_zona30.edg.xml"
if os.path.exists(mod_edg_path):
    result["modified_edge_file"]["exists"] = True
    result["modified_edge_file"]["mtime"] = os.path.getmtime(mod_edg_path)
    try:
        tree = ET.parse(mod_edg_path)
        count_833 = 0
        for edge in tree.findall('.//edge'):
            if edge.get('speed') and abs(float(edge.get('speed')) - 8.33) < 0.1:
                count_833 += 1
        result["modified_edge_file"]["valid"] = True
        result["modified_edge_file"]["edges_to_833"] = count_833
    except:
        pass

# Check Reimported Network
net_path = f"{ZONA30_DIR}/pasubio_zona30.net.xml"
if os.path.exists(net_path):
    result["reimported_net"]["exists"] = True
    try:
        tree = ET.parse(net_path)
        result["reimported_net"]["valid"] = True
        result["reimported_net"]["junctions"] = len(tree.findall('.//junction'))
        result["reimported_net"]["edges"] = len(tree.findall('.//edge'))
    except:
        pass

# Check SUMO Config
cfg_path = f"{ZONA30_DIR}/zona30.sumocfg"
if os.path.exists(cfg_path):
    result["sumo_config"]["exists"] = True
    try:
        tree = ET.parse(cfg_path)
        result["sumo_config"]["valid"] = True
        
        net_node = tree.find('.//net-file')
        if net_node is not None and net_node.get('value'):
            result["sumo_config"]["has_net"] = True
            
        route_node = tree.find('.//route-files')
        if route_node is not None and route_node.get('value'):
            result["sumo_config"]["has_routes"] = True
            
        tripinfo_node = tree.find('.//tripinfo-output')
        if tripinfo_node is not None and tripinfo_node.get('value'):
            result["sumo_config"]["has_tripinfo"] = True
    except:
        pass

# Check Simulation Output
tripinfo_path = f"{OUTPUT_DIR}/zona30_tripinfo.xml"
if os.path.exists(tripinfo_path):
    result["simulation_output"]["exists"] = True
    result["simulation_output"]["mtime"] = os.path.getmtime(tripinfo_path)
    try:
        tree = ET.parse(tripinfo_path)
        durations = [float(t.get('duration', 0)) for t in tree.findall('.//tripinfo')]
        result["simulation_output"]["valid"] = True
        result["simulation_output"]["trip_count"] = len(durations)
        result["simulation_output"]["avg_duration"] = sum(durations) / len(durations) if durations else 0
    except:
        pass

# Check Summary File
summary_path = f"{OUTPUT_DIR}/zona30_summary.txt"
if os.path.exists(summary_path):
    result["summary_file"]["exists"] = True
    with open(summary_path, 'r', errors='ignore') as f:
        result["summary_file"]["content"] = f.read()

# Save Result JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

chmod 666 /tmp/task_result.json

echo "=== Export complete ==="