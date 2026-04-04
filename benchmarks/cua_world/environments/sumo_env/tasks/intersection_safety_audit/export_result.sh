#!/bin/bash
echo "=== Exporting intersection_safety_audit result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import json
import os
import glob
import re
from datetime import datetime

OUTPUT_DIR = "/home/ga/SUMO_Output"
WORK_DIR = "/home/ga/SUMO_Scenarios/bologna_acosta"
RESULT_PATH = "/tmp/intersection_safety_audit_result.json"

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
    "ssm_exists": False,
    "ssm_size": 0,
    "ssm_has_conflicts": False,
    "ssm_configured": False,
    "sim_ran": False,
    "report_exists": False,
    "report_rows": 0,
    "report_content": "",
    "summary_exists": False,
    "summary_length": 0,
    "summary_content": "",
    "junction_info": {},
    "timestamp": datetime.now().isoformat()
}

# Check SSM output
ssm_path = os.path.join(OUTPUT_DIR, "ssm_output.xml")
if os.path.isfile(ssm_path):
    result["ssm_exists"] = True
    result["ssm_size"] = file_size(ssm_path)
    content = safe_read(ssm_path)
    if '<conflict' in content:
        result["ssm_has_conflicts"] = True

# Check report CSV
report_path = os.path.join(OUTPUT_DIR, "intersection_safety_report.csv")
if os.path.isfile(report_path):
    result["report_exists"] = True
    content = safe_read(report_path)
    result["report_content"] = content
    result["report_rows"] = len(content.strip().split('\n')) if content.strip() else 0

# Check summary
summary_path = os.path.join(OUTPUT_DIR, "safety_audit_summary.txt")
if os.path.isfile(summary_path):
    result["summary_exists"] = True
    content = safe_read(summary_path)
    result["summary_content"] = content
    result["summary_length"] = len(content)

# Check if simulation ran
tripinfo_path = os.path.join(WORK_DIR, "tripinfos.xml")
if os.path.isfile(tripinfo_path) and file_size(tripinfo_path) > 100:
    result["sim_ran"] = True

# Check for SSM device configuration
for pattern in [os.path.join(WORK_DIR, "*.sumocfg"), os.path.join(WORK_DIR, "*.cfg"),
                os.path.join(OUTPUT_DIR, "*.sumocfg")]:
    for f in glob.glob(pattern):
        content = safe_read(f)
        if re.search(r'ssm|surrogate', content, re.IGNORECASE):
            result["ssm_configured"] = True

# Also check bash history
bash_history = safe_read("/home/ga/.bash_history")
if re.search(r'device\.ssm|ssm\.measures', bash_history, re.IGNORECASE):
    result["ssm_configured"] = True

# Read junction info
junction_info_path = "/tmp/intersection_safety_junction_info.json"
if os.path.isfile(junction_info_path):
    try:
        with open(junction_info_path) as f:
            result["junction_info"] = json.load(f)
    except Exception:
        pass

with open(RESULT_PATH, "w") as f:
    json.dump(result, f, indent=2)

os.chmod(RESULT_PATH, 0o666)
print(json.dumps(result, indent=2))
PYEOF

echo "Result saved to /tmp/intersection_safety_audit_result.json"
echo "=== Export complete ==="
