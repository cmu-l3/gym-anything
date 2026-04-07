#!/bin/bash
set -e

echo "=== Exporting configure_essay_browser_features results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 << PYEOF > "$TEMP_JSON"
import json
import time
import subprocess
import os

def db_query(query):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout.strip()

try:
    start_time = float(open('/tmp/task_start_time.txt').read().strip())
except Exception:
    start_time = 0.0

try:
    with open('/tmp/baseline_config_count.txt') as f:
        baseline_count_str = f.read().strip()
    baseline_config_count = int(baseline_count_str) if baseline_count_str.isdigit() else 0
except Exception:
    baseline_config_count = 0

# Check for the requested config in the DB
config_exists_str = db_query("SELECT COUNT(*) FROM configuration_node WHERE name='ENGL101_Creative_Writing_2026' AND type='EXAM_CONFIG'")
config_exists = int(config_exists_str) if config_exists_str and config_exists_str.isdigit() else 0

config_id = ""
if config_exists > 0:
    config_id = db_query("SELECT id FROM configuration_node WHERE name='ENGL101_Creative_Writing_2026' AND type='EXAM_CONFIG' ORDER BY id DESC LIMIT 1")

current_config_count_str = db_query("SELECT COUNT(*) FROM configuration_node WHERE type='EXAM_CONFIG'")
current_config_count = int(current_config_count_str) if current_config_count_str and current_config_count_str.isdigit() else 0

new_configs = current_config_count - baseline_config_count

firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'config_exists': config_exists > 0,
    'config_id': config_id,
    'new_configs_created': new_configs,
    'baseline_config_count': baseline_config_count,
    'current_config_count': current_config_count,
    'firefox_running': firefox_running,
}

print(json.dumps(result, indent=2))
PYEOF

# Safely copy to standard output location with correct permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="