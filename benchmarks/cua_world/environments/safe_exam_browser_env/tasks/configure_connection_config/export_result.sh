#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting configure_connection_config results ==="

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
    with open('/tmp/seb_task_baseline_configure_connection_config.json') as f:
        baseline = json.load(f)
except Exception:
    pass

baseline_cc_count = baseline.get('connection_config_count', 0)

# Check for connection config named 'Campus Lockdown Browser Config'
config_exists = db_query(
    "SELECT COUNT(*) FROM seb_client_configuration WHERE name='Campus Lockdown Browser Config'"
)
config_exists = int(config_exists) if config_exists else 0

# Get config details
config_id = ""
config_active = False
config_fallback_url = ""
if config_exists > 0:
    config_id = db_query(
        "SELECT id FROM seb_client_configuration WHERE name='Campus Lockdown Browser Config' ORDER BY id DESC LIMIT 1"
    )
    if config_id:
        active_val = db_query(f"SELECT active FROM seb_client_configuration WHERE id={config_id}")
        config_active = active_val == '1' if active_val else False
        config_fallback_url = db_query(
            f"SELECT fallback_start_url FROM seb_client_configuration WHERE id={config_id}"
        ) or ""

# Count total connection configs now vs baseline
current_cc_count = int(db_query("SELECT COUNT(*) FROM seb_client_configuration") or 0)
new_configs = current_cc_count - baseline_cc_count

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    'config_exists': config_exists > 0,
    'config_name_match': config_exists > 0,
    'config_id': config_id,
    'config_active': config_active,
    'config_fallback_url': config_fallback_url,
    'new_configs_created': new_configs,
    'baseline_cc_count': baseline_cc_count,
    'current_cc_count': current_cc_count,
    'firefox_running': firefox_running,
}

with open('/tmp/configure_connection_config_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
