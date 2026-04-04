#!/bin/bash
echo "=== Exporting arterial_signal_coordination result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import json
import os
import xml.etree.ElementTree as ET
from datetime import datetime

WORK_DIR = "/home/ga/SUMO_Scenarios/bologna_acosta"
OUTPUT_DIR = "/home/ga/SUMO_Output"
RESULT_PATH = "/tmp/arterial_signal_coordination_result.json"

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
    "baseline_metrics_rows": 0,
    "coordinated_tls_exists": False,
    "coordinated_tls_size": 0,
    "coordinated_offsets": {},
    "num_modified_offsets": 0,
    "coordinated_cfg_exists": False,
    "coordinated_cfg_content": "",
    "coordinated_metrics_exists": False,
    "coordinated_metrics_content": "",
    "coordinated_metrics_rows": 0,
    "report_exists": False,
    "report_content": "",
    "report_length": 0,
    "tripinfo_baseline_exists": False,
    "tripinfo_coordinated_exists": False,
    "initial_data": {},
    "timestamp": datetime.now().isoformat()
}

# Load initial data
try:
    with open("/tmp/arterial_signal_coordination_initial_data.json") as f:
        result["initial_data"] = json.load(f)
except Exception:
    pass

# Check baseline metrics CSV
baseline_metrics_path = os.path.join(OUTPUT_DIR, "baseline_corridor_metrics.csv")
if os.path.isfile(baseline_metrics_path):
    result["baseline_metrics_exists"] = True
    content = safe_read(baseline_metrics_path)
    result["baseline_metrics_content"] = content
    result["baseline_metrics_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check coordinated TLS file
coord_tls_path = os.path.join(WORK_DIR, "acosta_tls_coordinated.add.xml")
if os.path.isfile(coord_tls_path):
    result["coordinated_tls_exists"] = True
    result["coordinated_tls_size"] = file_size(coord_tls_path)
    try:
        tree = ET.parse(coord_tls_path)
        root = tree.getroot()
        original_offsets = result.get("initial_data", {}).get("tls_offsets", {})
        modified_count = 0
        for tl in root.findall('tlLogic'):
            tid = tl.get('id', '')
            offset = tl.get('offset', '0')
            result["coordinated_offsets"][tid] = int(offset)
            orig_offset = original_offsets.get(tid, 0)
            if int(offset) != orig_offset:
                modified_count += 1
        result["num_modified_offsets"] = modified_count
    except Exception as e:
        result["tls_parse_error"] = str(e)

# Check coordinated sumocfg
coord_cfg_path = os.path.join(WORK_DIR, "run_coordinated.sumocfg")
if os.path.isfile(coord_cfg_path):
    result["coordinated_cfg_exists"] = True
    result["coordinated_cfg_content"] = safe_read(coord_cfg_path)

# Check coordinated metrics CSV
coord_metrics_path = os.path.join(OUTPUT_DIR, "coordinated_corridor_metrics.csv")
if os.path.isfile(coord_metrics_path):
    result["coordinated_metrics_exists"] = True
    content = safe_read(coord_metrics_path)
    result["coordinated_metrics_content"] = content
    result["coordinated_metrics_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check tripinfo files
for pattern in ["tripinfos.xml", "tripinfo*.xml", "*tripinfo*.xml"]:
    import glob
    for f in glob.glob(os.path.join(WORK_DIR, pattern)):
        if "coordinated" in f.lower() or "coord" in f.lower():
            result["tripinfo_coordinated_exists"] = True
        else:
            result["tripinfo_baseline_exists"] = True

# Also check output dir for tripinfo
for f in glob.glob(os.path.join(OUTPUT_DIR, "*tripinfo*")):
    if "coordinated" in f.lower() or "coord" in f.lower():
        result["tripinfo_coordinated_exists"] = True
    else:
        result["tripinfo_baseline_exists"] = True

# Check report
report_path = os.path.join(OUTPUT_DIR, "signal_coordination_report.txt")
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

echo "Result saved to /tmp/arterial_signal_coordination_result.json"
echo "=== Export complete ==="
