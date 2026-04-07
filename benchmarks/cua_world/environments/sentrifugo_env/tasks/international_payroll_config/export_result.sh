#!/bin/bash
echo "=== Exporting international_payroll_config result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to safely query the database and construct the JSON
# This avoids complicated Bash string escaping issues when dealing with tab-separated DB outputs
python3 << 'EOF'
import json
import subprocess
import time
import os

def run_query(sql):
    cmd = f'docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "{sql}"'
    try:
        return subprocess.check_output(cmd, shell=True, text=True).strip()
    except Exception as e:
        return ""

def count_records(sql):
    res = run_query(sql)
    return int(res) if res.isdigit() else 0

result = {
    "currencies": {
        "jpy_exists": count_records("SELECT COUNT(*) FROM main_currencies WHERE currencycode='JPY' AND isactive=1") > 0,
        "brl_exists": count_records("SELECT COUNT(*) FROM main_currencies WHERE currencycode='BRL' AND isactive=1") > 0,
        "inr_exists": count_records("SELECT COUNT(*) FROM main_currencies WHERE currencycode='INR' AND isactive=1") > 0
    },
    "pay_frequencies": {
        "semi_monthly_exists": count_records("SELECT COUNT(*) FROM main_payfrequency WHERE payfrequency='Semi-Monthly' AND isactive=1") > 0,
        "quarterly_exists": count_records("SELECT COUNT(*) FROM main_payfrequency WHERE payfrequency='Quarterly' AND isactive=1") > 0
    },
    "prefixes": {
        "dr_exists": count_records("SELECT COUNT(*) FROM main_prefix WHERE prefix='Dr.' AND isactive=1") > 0,
        "sra_exists": count_records("SELECT COUNT(*) FROM main_prefix WHERE prefix='Sra.' AND isactive=1") > 0,
        "sri_exists": count_records("SELECT COUNT(*) FROM main_prefix WHERE prefix='Sri' AND isactive=1") > 0
    },
    "department_exists": count_records("SELECT COUNT(*) FROM main_departments WHERE deptname='International Programs' AND isactive=1") > 0,
    "job_titles": {
        "cd_exists": count_records("SELECT COUNT(*) FROM main_jobtitles WHERE jobtitlename='Country Director' AND isactive=1") > 0,
        "rc_exists": count_records("SELECT COUNT(*) FROM main_jobtitles WHERE jobtitlename='Regional Coordinator' AND isactive=1") > 0
    },
    "employees": {}
}

for empid in ["EMP021", "EMP022", "EMP023"]:
    sql = f"SELECT u.firstname, u.lastname, d.deptname, j.jobtitlename FROM main_users u LEFT JOIN main_departments d ON u.department_id = d.id LEFT JOIN main_jobtitles j ON u.jobtitle_id = j.id WHERE u.employeeId='{empid}' AND u.isactive=1 LIMIT 1"
    row = run_query(sql)
    if row and '\t' in row:
        parts = row.split('\t')
        result["employees"][empid] = {
            "found": True,
            "firstname": parts[0],
            "lastname": parts[1] if len(parts) > 1 else "",
            "deptname": parts[2] if len(parts) > 2 else "",
            "jobtitle": parts[3] if len(parts) > 3 else ""
        }
    else:
        result["employees"][empid] = {"found": False}

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        result["task_start"] = int(f.read().strip())
except Exception:
    result["task_start"] = 0
result["task_end"] = int(time.time())

# Ensure the JSON is safely dumped
temp_json = "/tmp/task_result_temp.json"
with open(temp_json, "w") as f:
    json.dump(result, f)
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result_temp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_result_temp.json

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="