#!/bin/bash
echo "=== Exporting optimize_network_signal_timing result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import json
import os
import sys
import glob
import re
from datetime import datetime

WORK_DIR = "/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR = "/home/ga/SUMO_Output"
RESULT_PATH = "/tmp/optimize_network_signal_timing_result.json"
SUMO_HOME = os.environ.get("SUMO_HOME", "/usr/share/sumo")
sys.path.insert(0, os.path.join(SUMO_HOME, "tools"))

def safe_read(path):
    try:
        with open(path, "r", errors="replace") as f:
            return f.read()
    except Exception:
        return ""

def file_size(path):
    try:
        return os.path.getsize(path)
    except Exception:
        return 0

result = {
    "timestamp": datetime.now().isoformat(),
    # Optimized TLS file
    "optimized_tls_exists": False,
    "optimized_tls_size": 0,
    "optimized_tls_programs": {},
    "optimized_tls_num_modified": 0,
    # Optimized config
    "optimized_cfg_exists": False,
    "optimized_cfg_content": "",
    # Optimized simulation evidence
    "optimized_sim_ran": False,
    "optimized_edgedata_exists": False,
    "optimized_edgedata_size": 0,
    "optimized_tripinfo_exists": False,
    "optimized_tripinfo_size": 0,
    # Per-junction optimized delay (independently computed)
    "optimized_junction_delay": {},
    # Comparison report
    "report_exists": False,
    "report_content": "",
    "report_rows": 0,
    # Ground truth and initial data
    "ground_truth": {},
    "initial_data": {},
}

# ── Check optimized TLS file ──
opt_tls_path = os.path.join(WORK_DIR, "pasubio_tls_optimized.add.xml")
if os.path.isfile(opt_tls_path):
    result["optimized_tls_exists"] = True
    result["optimized_tls_size"] = file_size(opt_tls_path)
    try:
        import xml.etree.ElementTree as ET
        tree = ET.parse(opt_tls_path)
        root = tree.getroot()
        for tl in root.findall("tlLogic"):
            tls_id = tl.get("id")
            phases = tl.findall("phase")
            durations = [int(p.get("duration", 0)) for p in phases]
            states = [p.get("state", "") for p in phases]
            result["optimized_tls_programs"][tls_id] = {
                "durations": durations,
                "states": states,
                "num_phases": len(phases),
                "cycle_length": sum(durations),
            }
    except Exception as e:
        result["optimized_tls_parse_error"] = str(e)

    # Count how many TLS programs differ from the suboptimal (equal-split) baseline
    try:
        with open("/tmp/optimize_signal_initial_data.json") as f:
            idata = json.load(f)
        suboptimal = idata.get("suboptimal_durations", {})
        num_modified = 0
        for tls_id, prog in result["optimized_tls_programs"].items():
            if tls_id in suboptimal:
                if prog["durations"] != suboptimal[tls_id]:
                    num_modified += 1
        result["optimized_tls_num_modified"] = num_modified
    except Exception:
        pass

# ── Check optimized config ──
opt_cfg_path = os.path.join(WORK_DIR, "run_optimized.sumocfg")
if os.path.isfile(opt_cfg_path):
    result["optimized_cfg_exists"] = True
    result["optimized_cfg_content"] = safe_read(opt_cfg_path)

# ── Check for optimized simulation output ──
# Look for edgedata and tripinfo files that are NOT from baseline
for pattern in [os.path.join(WORK_DIR, "edgedata*.xml"),
                os.path.join(OUTPUT_DIR, "edgedata*.xml")]:
    for f in glob.glob(pattern):
        base = os.path.basename(f)
        if "baseline" not in base and file_size(f) > 500:
            result["optimized_edgedata_exists"] = True
            result["optimized_edgedata_size"] = file_size(f)
            # Compute per-junction delay from optimized edgedata
            try:
                import sumolib
                net = sumolib.net.readNet(os.path.join(WORK_DIR, "pasubio_buslanes.net.xml"))
                TLS_IDS = ["218", "219", "220", "230", "231", "232", "233", "282"]

                junction_edges = {}
                edge_freeflow = {}
                for tls_id in TLS_IDS:
                    try:
                        tls = net.getTLS(tls_id)
                        incoming = set()
                        for conn in tls.getConnections():
                            edge_id = conn[0].getEdge().getID()
                            if not edge_id.startswith(":"):
                                incoming.add(edge_id)
                        junction_edges[tls_id] = sorted(incoming)
                        for eid in junction_edges[tls_id]:
                            try:
                                edge = net.getEdge(eid)
                                if edge.getSpeed() > 0:
                                    edge_freeflow[eid] = edge.getLength() / edge.getSpeed()
                            except Exception:
                                pass
                    except Exception:
                        junction_edges[tls_id] = []

                import xml.etree.ElementTree as ET
                etree = ET.parse(f)
                eroot = etree.getroot()
                edge_traveltime = {}
                edge_entered = {}
                for interval in eroot.findall("interval"):
                    for edge_el in interval.findall("edge"):
                        eid = edge_el.get("id")
                        tt_str = edge_el.get("traveltime")
                        entered_str = edge_el.get("entered")
                        if tt_str and eid:
                            if eid not in edge_traveltime:
                                edge_traveltime[eid] = []
                                edge_entered[eid] = []
                            edge_traveltime[eid].append(float(tt_str))
                            edge_entered[eid].append(
                                int(float(entered_str)) if entered_str else 0)

                edge_avg_tt = {eid: sum(tts)/len(tts)
                               for eid, tts in edge_traveltime.items()}
                edge_total_entered = {eid: sum(ents)
                                      for eid, ents in edge_entered.items()}

                opt_junction_delay = {}
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
                        opt_junction_delay[tls_id] = round(
                            total_delay_veh / total_vehicles, 2)
                    else:
                        opt_junction_delay[tls_id] = 0.0

                result["optimized_junction_delay"] = opt_junction_delay
            except Exception as e:
                result["optimized_delay_error"] = str(e)
            break  # Use first matching edgedata file

for pattern in [os.path.join(WORK_DIR, "tripinfo*.xml"),
                os.path.join(OUTPUT_DIR, "tripinfo*.xml")]:
    for f in glob.glob(pattern):
        base = os.path.basename(f)
        if "baseline" not in base and file_size(f) > 500:
            result["optimized_tripinfo_exists"] = True
            result["optimized_tripinfo_size"] = file_size(f)
            result["optimized_sim_ran"] = True
            break

# ── Check comparison report ──
report_path = os.path.join(OUTPUT_DIR, "intersection_optimization_report.csv")
if os.path.isfile(report_path):
    result["report_exists"] = True
    content = safe_read(report_path)
    result["report_content"] = content
    result["report_rows"] = len(content.strip().split("\n")) if content.strip() else 0

# ── Load ground truth and initial data ──
for path, key in [("/tmp/optimize_signal_ground_truth.json", "ground_truth"),
                   ("/tmp/optimize_signal_initial_data.json", "initial_data")]:
    if os.path.isfile(path):
        try:
            with open(path) as f:
                result[key] = json.load(f)
        except Exception:
            pass

# ── Write result ──
with open(RESULT_PATH, "w") as f:
    json.dump(result, f, indent=2)
os.chmod(RESULT_PATH, 0o666)
print(json.dumps(result, indent=2))
PYEOF

echo "Result saved to /tmp/optimize_network_signal_timing_result.json"
echo "=== Export complete ==="
