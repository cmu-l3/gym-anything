#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting import_configure_exam results ==="

take_screenshot /tmp/final_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

python3 << 'PYEOF'
import json
import time
import subprocess

def db_query(query):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout.strip()

start_time = float(open('/tmp/task_start_time.txt').read().strip())

# Load baseline
baseline = {}
try:
    with open('/tmp/seb_task_baseline_import_configure_exam.json') as f:
        baseline = json.load(f)
except Exception:
    pass

baseline_exam_count = baseline.get('exam_count', 0)
baseline_indicator_count = baseline.get('indicator_count', 0)

# Count current exams
current_exam_count = int(db_query("SELECT COUNT(*) FROM exam") or 0)
new_exams = current_exam_count - baseline_exam_count

# Get details of newly created exams
new_exam_details = []
if new_exams > 0:
    exam_rows = db_query(
        f"SELECT id, external_id, status FROM exam ORDER BY id DESC LIMIT {new_exams}"
    )
    if exam_rows:
        for row in exam_rows.split('\n'):
            if row.strip():
                parts = row.strip().split('\t')
                if len(parts) >= 3:
                    exam_id = parts[0]
                    new_exam_details.append({
                        'id': exam_id,
                        'external_id': parts[1],
                        'status': parts[2],
                    })

# Check for indicators on new exams
exam_indicators = []
for exam in new_exam_details:
    indicators = db_query(
        f"SELECT id, name, type FROM indicator WHERE exam_id={exam['id']}"
    )
    if indicators:
        for row in indicators.split('\n'):
            if row.strip():
                parts = row.strip().split('\t')
                if len(parts) >= 3:
                    exam_indicators.append({
                        'exam_id': exam['id'],
                        'indicator_id': parts[0],
                        'name': parts[1],
                        'type': parts[2],
                    })

current_indicator_count = int(db_query("SELECT COUNT(*) FROM indicator") or 0)
new_indicators = current_indicator_count - baseline_indicator_count

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    'new_exams_created': new_exams,
    'new_exam_details': new_exam_details,
    'exam_indicators': exam_indicators,
    'new_indicators_created': new_indicators,
    'baseline_exam_count': baseline_exam_count,
    'current_exam_count': current_exam_count,
    'baseline_indicator_count': baseline_indicator_count,
    'current_indicator_count': current_indicator_count,
    'exam_imported': new_exams > 0,
    'indicator_added': new_indicators > 0,
    'firefox_running': firefox_running,
}

with open('/tmp/import_configure_exam_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
