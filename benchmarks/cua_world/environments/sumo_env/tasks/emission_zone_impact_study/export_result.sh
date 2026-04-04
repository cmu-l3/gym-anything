#!/bin/bash
echo "=== Exporting emission_zone_impact_study result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import json
import os
import glob
import xml.etree.ElementTree as ET
from datetime import datetime

WORK_DIR = "/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR = "/home/ga/SUMO_Output"
RESULT_PATH = "/tmp/emission_zone_impact_study_result.json"

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
    "baseline_em_exists": False,
    "baseline_em_size": 0,
    "lez_em_exists": False,
    "lez_em_size": 0,
    "modifications": {
        "edges_with_disallow": 0,
        "net_modified": False,
        "vtypes_modified": False,
        "routes_modified": False,
        "strategies_used": 0
    },
    "report_exists": False,
    "report_rows": 0,
    "report_content": "",
    "summary_exists": False,
    "summary_length": 0,
    "summary_content": "",
    "initial_data": {},
    "timestamp": datetime.now().isoformat()
}

# Check baseline emissions
baseline_path = os.path.join(OUTPUT_DIR, "baseline_emissions.xml")
if os.path.isfile(baseline_path):
    result["baseline_em_exists"] = True
    result["baseline_em_size"] = file_size(baseline_path)

# Check LEZ emissions
lez_path = os.path.join(OUTPUT_DIR, "lez_emissions.xml")
if os.path.isfile(lez_path):
    result["lez_em_exists"] = True
    result["lez_em_size"] = file_size(lez_path)

# Load initial data
initial = {}
try:
    with open("/tmp/emission_zone_initial_data.json") as f:
        initial = json.load(f)
except Exception:
    pass
result["initial_data"] = initial

# Check for network modifications (disallow attributes)
net_file = os.path.join(WORK_DIR, "pasubio_buslanes.net.xml")
disallow_count = 0
net_modified = False
try:
    tree = ET.parse(net_file)
    root = tree.getroot()
    for edge in root.findall('edge'):
        eid = edge.get('id', '')
        if eid.startswith(':'):
            continue
        for lane in edge.findall('lane'):
            disallow = lane.get('disallow', '')
            if disallow:
                disallow_count += 1
                net_modified = True
                break
except Exception:
    pass

# Check if vehicle types were modified
vtypes_modified = False
try:
    tree = ET.parse(os.path.join(WORK_DIR, "pasubio_vtypes.add.xml"))
    root = tree.getroot()
    orig_classes = initial.get("emission_classes", {})
    for vtype in root.iter('vType'):
        vid = vtype.get('id', '')
        eclass = vtype.get('emissionClass', '')
        if vid in orig_classes and eclass != orig_classes[vid]:
            vtypes_modified = True
            break
except Exception:
    pass

# Check for modified route files
routes_modified = False
try:
    for f in os.listdir(WORK_DIR):
        if f.endswith('.rou.xml') and ('lez' in f.lower() or 'modified' in f.lower() or 'clean' in f.lower()):
            routes_modified = True
            break
except Exception:
    pass

strategies_used = sum([net_modified, vtypes_modified, routes_modified])
result["modifications"] = {
    "edges_with_disallow": disallow_count,
    "net_modified": net_modified,
    "vtypes_modified": vtypes_modified,
    "routes_modified": routes_modified,
    "strategies_used": strategies_used
}

# Check report
report_path = os.path.join(OUTPUT_DIR, "emission_impact_report.csv")
if os.path.isfile(report_path):
    result["report_exists"] = True
    content = safe_read(report_path)
    result["report_content"] = content
    result["report_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check summary
summary_path = os.path.join(OUTPUT_DIR, "emission_impact_summary.txt")
if os.path.isfile(summary_path):
    result["summary_exists"] = True
    content = safe_read(summary_path)
    result["summary_content"] = content
    result["summary_length"] = len(content)

with open(RESULT_PATH, "w") as f:
    json.dump(result, f, indent=2)

os.chmod(RESULT_PATH, 0o666)
print(json.dumps(result, indent=2))
PYEOF

echo "Result saved to /tmp/emission_zone_impact_study_result.json"
echo "=== Export complete ==="
