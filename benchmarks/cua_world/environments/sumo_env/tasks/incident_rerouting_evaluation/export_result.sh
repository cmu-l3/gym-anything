#!/bin/bash
echo "=== Exporting incident_rerouting_evaluation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import json
import os
import glob
import xml.etree.ElementTree as ET
from datetime import datetime

WORK_DIR = "/home/ga/SUMO_Scenarios/bologna_acosta"
OUTPUT_DIR = "/home/ga/SUMO_Output"
RESULT_PATH = "/tmp/incident_rerouting_evaluation_result.json"

def safe_read(path):
    try:
        with open(path, 'r', errors='replace') as f:
            return f.read()
    except Exception:
        return ""

def file_size(path):
    try:
        return os.path.getsize(path)
    except Exception:
        return 0

result = {
    "baseline_metrics_exists": False,
    "baseline_metrics_content": "",
    "rerouter_file_exists": False,
    "rerouter_file_size": 0,
    "rerouter_count": 0,
    "closed_edges": [],
    "rerouter_has_closing": False,
    "rerouter_has_dest_prob": False,
    "incident_cfg_exists": False,
    "incident_cfg_content": "",
    "incident_metrics_exists": False,
    "incident_metrics_content": "",
    "report_exists": False,
    "report_content": "",
    "report_length": 0,
    "tripinfo_baseline_exists": False,
    "tripinfo_incident_exists": False,
    "initial_data": {},
    "timestamp": datetime.now().isoformat()
}

# Load initial data
try:
    with open("/tmp/incident_rerouting_evaluation_initial_data.json") as f:
        result["initial_data"] = json.load(f)
except Exception:
    pass

# Check baseline metrics CSV
baseline_path = os.path.join(OUTPUT_DIR, "baseline_network_performance.csv")
if os.path.isfile(baseline_path):
    result["baseline_metrics_exists"] = True
    result["baseline_metrics_content"] = safe_read(baseline_path)

# Check rerouter file
rerouter_path = os.path.join(WORK_DIR, "incident_rerouters.add.xml")
if os.path.isfile(rerouter_path):
    result["rerouter_file_exists"] = True
    result["rerouter_file_size"] = file_size(rerouter_path)
    try:
        tree = ET.parse(rerouter_path)
        root = tree.getroot()
        rerouters = root.findall('.//rerouter')
        result["rerouter_count"] = len(rerouters)
        closed_edges = set()
        for rr in rerouters:
            edges = rr.get('edges', '')
            for e in edges.split():
                if e.strip():
                    closed_edges.add(e.strip())
            # Check for closingReroute
            for cr in rr.iter('closingReroute'):
                result["rerouter_has_closing"] = True
            for cr in rr.iter('closingLaneReroute'):
                result["rerouter_has_closing"] = True
            # Check for destProbReroute
            for dp in rr.iter('destProbReroute'):
                result["rerouter_has_dest_prob"] = True
            for dp in rr.iter('routeProbReroute'):
                result["rerouter_has_dest_prob"] = True
        result["closed_edges"] = list(closed_edges)
    except Exception as e:
        result["rerouter_parse_error"] = str(e)

# Check incident sumocfg
incident_cfg_path = os.path.join(WORK_DIR, "run_incident.sumocfg")
if os.path.isfile(incident_cfg_path):
    result["incident_cfg_exists"] = True
    result["incident_cfg_content"] = safe_read(incident_cfg_path)

# Check incident metrics CSV
incident_metrics_path = os.path.join(OUTPUT_DIR, "incident_network_performance.csv")
if os.path.isfile(incident_metrics_path):
    result["incident_metrics_exists"] = True
    result["incident_metrics_content"] = safe_read(incident_metrics_path)

# Check tripinfo files
for f in glob.glob(os.path.join(WORK_DIR, "*tripinfo*")):
    if "incident" in f.lower():
        result["tripinfo_incident_exists"] = True
    else:
        result["tripinfo_baseline_exists"] = True
for f in glob.glob(os.path.join(OUTPUT_DIR, "*tripinfo*")):
    if "incident" in f.lower():
        result["tripinfo_incident_exists"] = True
    else:
        result["tripinfo_baseline_exists"] = True

# Check report
report_path = os.path.join(OUTPUT_DIR, "incident_assessment_report.txt")
if os.path.isfile(report_path):
    result["report_exists"] = True
    content = safe_read(report_path)
    result["report_content"] = content
    result["report_length"] = len(content)

with open(RESULT_PATH, "w") as f:
    json.dump(result, f, indent=2)

os.chmod(RESULT_PATH, 0o666)
print(json.dumps(result, indent=2))
PYEOF

echo "Result saved to /tmp/incident_rerouting_evaluation_result.json"
echo "=== Export complete ==="
