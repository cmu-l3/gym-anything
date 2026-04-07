#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting upload_seb_certificate results ==="

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

python3 << 'PYEOF'
import json
import time
import subprocess
import os

def db_query(query):
    try:
        result = subprocess.run(
            ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
             '-psebserver123', 'SEBServer', '-N', '-e', query],
            capture_output=True, text=True, timeout=10
        )
        return result.stdout.strip()
    except Exception as e:
        return ""

# Get task start time
start_time = 0
if os.path.exists('/tmp/task_start_time.txt'):
    try:
        start_time = float(open('/tmp/task_start_time.txt').read().strip())
    except:
        pass

# Get baseline count
baseline_count = 0
if os.path.exists('/tmp/initial_cert_count.txt'):
    try:
        baseline_count = int(open('/tmp/initial_cert_count.txt').read().strip())
    except:
        pass

# Check current count in certificate table
current_count_str = db_query("SELECT COUNT(*) FROM certificate")
current_count = int(current_count_str) if current_count_str and current_count_str.isdigit() else 0

new_certs = current_count - baseline_count

# Check if the specific certificate alias was uploaded
cert_exists = False
cert_details = ""
if current_count > 0:
    # Try multiple common column names (alias, name) to be robust against DB schema versions
    match_count = db_query("SELECT COUNT(*) FROM certificate WHERE alias LIKE '%UniversityExamCert2025%' OR name LIKE '%UniversityExamCert2025%'")
    if match_count and match_count.isdigit() and int(match_count) > 0:
        cert_exists = True
        cert_details = db_query("SELECT id FROM certificate WHERE alias LIKE '%UniversityExamCert2025%' OR name LIKE '%UniversityExamCert2025%' LIMIT 1")

# Check if Firefox is still running
firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'baseline_cert_count': baseline_count,
    'current_cert_count': current_count,
    'new_certs_created': max(0, new_certs),
    'target_cert_exists': cert_exists,
    'cert_details': cert_details,
    'firefox_running': firefox_running
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Ensure file is readable by the verifier
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="