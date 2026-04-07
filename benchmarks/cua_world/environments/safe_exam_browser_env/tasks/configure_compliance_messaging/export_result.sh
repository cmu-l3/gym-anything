#!/bin/bash
echo "=== Exporting configure_compliance_messaging results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot as evidence
take_screenshot /tmp/final_screenshot.png

# Extract final state into JSON using Python for safe parsing
python3 << 'PYEOF'
import json
import time
import subprocess
import os

def db_query(query):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-B', '-e', query],
        capture_output=True, text=True
    )
    return result.stdout.strip()

start_time = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except Exception:
    pass

# Extract all configuration attributes and values for "Law 101 Final"
raw_settings = db_query("""
SELECT ca.key_name, cv.value
FROM configuration_value cv
JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id
JOIN configuration_node cn ON cn.active_configuration_id = cv.configuration_id
WHERE cn.name = 'Law 101 Final'
""")

settings = {}
if raw_settings:
    for line in raw_settings.split('\n'):
        parts = line.split('\t', 1)
        if len(parts) == 2:
            settings[parts[0]] = parts[1]

# Check if application is running
firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'settings': settings,
    'firefox_running': firefox_running,
}

# Write securely to tmp
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported JSON result successfully.")
PYEOF

# Ensure proper permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="