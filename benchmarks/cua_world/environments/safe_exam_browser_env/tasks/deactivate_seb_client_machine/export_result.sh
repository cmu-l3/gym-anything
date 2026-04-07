#!/bin/bash
set -e

echo "=== Exporting deactivate_seb_client_machine results ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

python3 << 'PYEOF'
import json
import time
import subprocess

def db_query(query):
    try:
        result = subprocess.run(
            ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
             '-psebserver123', 'SEBServer', '-N', '-e', query],
            capture_output=True, text=True, timeout=30
        )
        return result.stdout.strip()
    except Exception:
        return ""

start_time = float(open('/tmp/task_start_time.txt').read().strip())
end_time = time.time()

# Check seb_client_configuration table
cc_exists = db_query("SELECT COUNT(*) FROM seb_client_configuration WHERE name='Loaner-Laptop-22'")
cc_exists = int(cc_exists) if cc_exists and cc_exists.isdigit() else 0
cc_active = db_query("SELECT active FROM seb_client_configuration WHERE name='Loaner-Laptop-22' ORDER BY id DESC LIMIT 1")

# Check configuration_node table
node_exists = db_query("SELECT COUNT(*) FROM configuration_node WHERE name='Loaner-Laptop-22'")
node_exists = int(node_exists) if node_exists and node_exists.isdigit() else 0
node_active = db_query("SELECT active FROM configuration_node WHERE name='Loaner-Laptop-22' ORDER BY id DESC LIMIT 1")

# Detect Firefox running state
firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'task_start_time': start_time,
    'task_end_time': end_time,
    'duration_seconds': end_time - start_time,
    'seb_client_config': {
        'exists': cc_exists > 0,
        'active_status': cc_active
    },
    'configuration_node': {
        'exists': node_exists > 0,
        'active_status': node_active
    },
    'firefox_running': firefox_running
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="