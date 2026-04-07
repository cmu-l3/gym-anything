#!/bin/bash
echo "=== Exporting merge_duplicate_contacts results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/merge_duplicate_contacts_final.png

# Query the database state and export via Python to safely construct JSON
cat << 'EOF' > /tmp/export_helper.py
import subprocess
import json
import os

def run_query(query):
    try:
        cmd = ["docker", "exec", "-i", "suitecrm-db", "mysql", "-u", "suitecrm", "-psuitecrm_pass", "suitecrm", "-e", query]
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
        if not result:
            return []
        lines = result.split('\n')
        if len(lines) < 2:
            return []
        headers = lines[0].split('\t')
        rows = []
        for line in lines[1:]:
            rows.append(dict(zip(headers, line.split('\t'))))
        return rows
    except Exception as e:
        return []

# Load the exact target IDs created in setup
uuids = {}
if os.path.exists("/tmp/task_uuids.json"):
    with open("/tmp/task_uuids.json", "r") as f:
        uuids = json.load(f)

uuid_a = uuids.get('uuid_a', '')
uuid_b = uuids.get('uuid_b', '')

# Check statuses of the two specific original records
active_target_rows = run_query(f"SELECT id FROM contacts WHERE id IN ('{uuid_a}','{uuid_b}') AND deleted=0")
active_target_uuids = [r['id'] for r in active_target_rows]

deleted_target_rows = run_query(f"SELECT id FROM contacts WHERE id IN ('{uuid_a}','{uuid_b}') AND deleted=1")
deleted_target_uuids = [r['id'] for r in deleted_target_rows]

# Check for any rogue new records created manually instead of merging
extra_active_rows = run_query(f"SELECT id FROM contacts WHERE first_name='Maria' AND last_name='Thornton-Garcia' AND deleted=0 AND id NOT IN ('{uuid_a}','{uuid_b}')")

# Fetch full profile of the active "Maria Thornton-Garcia" records
all_active = run_query("SELECT c.id, c.title, c.phone_work, c.primary_address_postalcode, c.description, ea.email_address, UNIX_TIMESTAMP(c.date_modified) as mtime FROM contacts c LEFT JOIN email_addr_bean_rel eabr ON c.id=eabr.bean_id AND eabr.bean_module='Contacts' AND eabr.deleted=0 AND eabr.primary_address=1 LEFT JOIN email_addresses ea ON eabr.email_address_id=ea.id AND ea.deleted=0 WHERE c.first_name='Maria' AND c.last_name='Thornton-Garcia' AND c.deleted=0")

# Fetch start time for timestamp validation
start_time = 0
if os.path.exists("/tmp/task_start_time.txt"):
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            start_time = int(f.read().strip())
    except:
        pass

out = {
    "active_target_uuids": active_target_uuids,
    "deleted_target_uuids": deleted_target_uuids,
    "extra_active_count": len(extra_active_rows),
    "total_active_count": len(all_active),
    "survivor": all_active[0] if len(all_active) == 1 else None,
    "task_start_time": start_time
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(out, f, indent=2)
EOF

python3 /tmp/export_helper.py
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== export complete ==="