#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting create_exam_template results ==="

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
    with open('/tmp/seb_task_baseline_create_exam_template.json') as f:
        baseline = json.load(f)
except Exception:
    pass

baseline_template_count = baseline.get('exam_template_count', 0)
baseline_indicator_count = baseline.get('indicator_count', 0)

# Check for exam template named 'Midterm Proctored Exam Template'
template_exists = db_query(
    "SELECT COUNT(*) FROM exam_template WHERE name='Midterm Proctored Exam Template'"
)
template_exists = int(template_exists) if template_exists else 0

# Get template details
template_id = ""
template_description = ""
if template_exists > 0:
    template_id = db_query(
        "SELECT id FROM exam_template WHERE name='Midterm Proctored Exam Template' ORDER BY id DESC LIMIT 1"
    )
    if template_id:
        template_description = db_query(
            f"SELECT description FROM exam_template WHERE id={template_id}"
        ) or ""

# Check for indicators associated with the template
indicators = []
if template_id:
    indicator_rows = db_query(
        f"SELECT id, name, type FROM indicator WHERE exam_template_id={template_id}"
    )
    if indicator_rows:
        for row in indicator_rows.split('\n'):
            if row.strip():
                parts = row.strip().split('\t')
                if len(parts) >= 3:
                    indicators.append({
                        'id': parts[0],
                        'name': parts[1],
                        'type': parts[2],
                    })

# Count totals vs baseline
current_template_count = int(db_query("SELECT COUNT(*) FROM exam_template") or 0)
current_indicator_count = int(db_query("SELECT COUNT(*) FROM indicator") or 0)
new_templates = current_template_count - baseline_template_count
new_indicators = current_indicator_count - baseline_indicator_count

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    'template_exists': template_exists > 0,
    'template_name_match': template_exists > 0,
    'template_id': template_id,
    'template_description': template_description,
    'indicators': indicators,
    'indicator_count': len(indicators),
    'new_templates_created': new_templates,
    'new_indicators_created': new_indicators,
    'baseline_template_count': baseline_template_count,
    'baseline_indicator_count': baseline_indicator_count,
    'current_template_count': current_template_count,
    'current_indicator_count': current_indicator_count,
    'firefox_running': firefox_running,
}

with open('/tmp/create_exam_template_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
