#!/bin/bash
echo "=== Exporting link_exam_security_policies results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot for trajectory mapping
take_screenshot /tmp/task_final.png

python3 << 'PYEOF'
import subprocess
import json
import time

def run_sql(sql):
    res = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root', '-psebserver123', 'SEBServer', '-N', '-e', sql], 
        capture_output=True, text=True
    )
    return res.stdout.strip()

# Dynamically query schema columns to avoid brittleness against version updates
columns_out = run_sql("SHOW COLUMNS FROM exam")
col_names = [line.split('\t')[0] for line in columns_out.split('\n') if line]

# Find foreign key columns robustly
template_col = next((c for c in col_names if 'template' in c.lower()), 'exam_template_id')
config_col = next((c for c in col_names if 'client_config' in c.lower() or 'seb_client' in c.lower() or 'connection' in c.lower()), 'seb_client_configuration_id')

# Fetch IDs of the target entities
exam_id = run_sql("SELECT id FROM exam WHERE name = 'Physics 301 Midterm' ORDER BY id DESC LIMIT 1")
target_template_id = run_sql("SELECT id FROM exam_template WHERE name = 'High Security Template' ORDER BY id DESC LIMIT 1")
target_config_id = run_sql("SELECT id FROM seb_client_configuration WHERE name = 'Campus BYOD Config' ORDER BY id DESC LIMIT 1")

# Fetch linked foreign keys from the exam record
linked_template_id = run_sql(f"SELECT {template_col} FROM exam WHERE id = {exam_id}") if exam_id else None
linked_config_id = run_sql(f"SELECT {config_col} FROM exam WHERE id = {exam_id}") if exam_id else None

# Check valid linkage
template_linked_correctly = bool(exam_id) and bool(target_template_id) and str(linked_template_id) == str(target_template_id)
config_linked_correctly = bool(exam_id) and bool(target_config_id) and str(linked_config_id) == str(target_config_id)

result = {
    "exam_found": bool(exam_id),
    "template_found": bool(target_template_id),
    "config_found": bool(target_config_id),
    "linked_template_id": linked_template_id,
    "target_template_id": target_template_id,
    "template_linked_correctly": template_linked_correctly,
    "linked_config_id": linked_config_id,
    "target_config_id": target_config_id,
    "config_linked_correctly": config_linked_correctly,
    "timestamp": time.time()
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions on exported JSON
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="