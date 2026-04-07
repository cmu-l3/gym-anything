#!/bin/bash
echo "=== Exporting create_cases_by_priority_report results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

CURRENT_REPORT_COUNT=$(suitecrm_count "aor_reports" "deleted=0")

# We use an embedded Python script to safely query MariaDB and serialize the complex 
# AOR Report structure (spanning 4 relational tables) cleanly into JSON.
cat << 'PYEOF' > /tmp/export_db.py
import subprocess
import json
import time
import sys

def run_query(query):
    # Run query via docker exec
    cmd = f"docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -e \"{query}\" 2>/dev/null"
    try:
        output = subprocess.check_output(cmd, shell=True, text=True).strip()
        if not output:
            return []
        lines = output.split('\n')
        headers = lines[0].split('\t')
        results = []
        for line in lines[1:]:
            values = line.split('\t')
            # Handle empty trailing values
            if len(values) < len(headers):
                values.extend([''] * (len(headers) - len(values)))
            results.append(dict(zip(headers, values)))
        return results
    except Exception as e:
        return []

# 1. Check for the Report Record itself
report_data = run_query("SELECT id, name, report_module, UNIX_TIMESTAMP(date_entered) as date_entered FROM aor_reports WHERE name='Active Cases by Priority' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")

report_found = len(report_data) > 0
report_info = report_data[0] if report_found else {}
report_id = report_info.get('id', '')

conditions = []
fields = []
charts = []

# 2. Fetch all relational configurations if report was created
if report_id:
    conditions = run_query(f"SELECT * FROM aor_conditions WHERE aor_report_id='{report_id}' AND deleted=0")
    fields = run_query(f"SELECT * FROM aor_fields WHERE aor_report_id='{report_id}' AND deleted=0")
    charts = run_query(f"SELECT * FROM aor_charts WHERE aor_report_id='{report_id}' AND deleted=0")

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

try:
    with open("/tmp/initial_report_count.txt", "r") as f:
        initial_count = int(f.read().strip())
except Exception:
    initial_count = 0

current_count = int(sys.argv[1]) if len(sys.argv) > 1 else 0

out = {
    "task_start": task_start,
    "task_end": int(time.time()),
    "initial_count": initial_count,
    "current_count": current_count,
    "report_found": report_found,
    "report": report_info,
    "conditions": conditions,
    "fields": fields,
    "charts": charts
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(out, f, indent=2)
PYEOF

python3 /tmp/export_db.py "$CURRENT_REPORT_COUNT"

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="