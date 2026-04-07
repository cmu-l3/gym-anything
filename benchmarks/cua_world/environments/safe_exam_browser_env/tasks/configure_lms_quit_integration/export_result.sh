#!/bin/bash
set -e
echo "=== Exporting configure_lms_quit_integration results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot as evidence
take_screenshot /tmp/task_final.png

# Export database dump for verifier to safely search for the deeply nested Quit URL
echo "Dumping database for state verification..."
docker exec seb-server-mariadb mysqldump -u root -psebserver123 SEBServer > /tmp/seb_dump.sql 2>/dev/null || true

python3 << 'PYEOF'
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

# Retrieve timestamps
start_time_str = ""
if os.path.exists('/tmp/task_start_time.txt'):
    start_time_str = open('/tmp/task_start_time.txt').read().strip()
start_time = float(start_time_str) if start_time_str else 0.0

initial_count_str = ""
if os.path.exists('/tmp/initial_config_count.txt'):
    initial_count_str = open('/tmp/initial_config_count.txt').read().strip()
initial_count = int(initial_count_str) if initial_count_str else 0

# Check for the specific configuration
config_exists_str = db_query("SELECT COUNT(*) FROM configuration_node WHERE name='Biology Final - Moodle AutoQuit' AND type='EXAM_CONFIG'")
config_exists = int(config_exists_str) > 0 if config_exists_str.isdigit() else False

current_count_str = db_query("SELECT COUNT(*) FROM configuration_node WHERE type='EXAM_CONFIG'")
current_count = int(current_count_str) if current_count_str.isdigit() else 0

new_configs_created = current_count > initial_count

# Verify Firefox is still open
firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'task_start': start_time,
    'task_end': time.time(),
    'initial_config_count': initial_count,
    'current_config_count': current_count,
    'new_configs_created': new_configs_created,
    'config_exists': config_exists,
    'firefox_running': firefox_running
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export Summary:")
print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions allow copying
chmod 666 /tmp/task_result.json /tmp/seb_dump.sql /tmp/task_final.png /tmp/task_start_screenshot.png 2>/dev/null || sudo chmod 666 /tmp/task_result.json /tmp/seb_dump.sql /tmp/task_final.png /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Export complete ==="