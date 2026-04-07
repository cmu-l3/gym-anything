#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting configure_custom_user_agent results ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Python script to safely query the MariaDB instance and export structured JSON
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
            capture_output=True, text=True, timeout=30
        )
        return result.stdout.strip()
    except Exception as e:
        print(f"DB Query Error: {e}")
        return ""

start_time = float(open('/tmp/task_start_time.txt').read().strip())
config_name = "Engineering Legacy Final 2026"
target_suffix = "EngDept/LegacyAuth-v9"

# 1. Check if the configuration node was created
node_id_str = db_query(f"SELECT id FROM configuration_node WHERE name='{config_name}' ORDER BY id DESC LIMIT 1")
config_exists = bool(node_id_str and node_id_str.isdigit())

attributes = {}
# 2. Extract configuration attributes if the node exists
if config_exists:
    node_id = int(node_id_str)
    # Get the active configuration ID for this node
    config_id_str = db_query(f"SELECT current_configuration_id FROM configuration_node WHERE id={node_id}")
    if not config_id_str or not config_id_str.isdigit() or config_id_str == 'NULL':
        config_id_str = db_query(f"SELECT id FROM configuration WHERE configuration_node_id={node_id} ORDER BY id DESC LIMIT 1")

    if config_id_str and config_id_str.isdigit():
        config_id = int(config_id_str)
        # Fetch all key-value settings for this configuration
        query = f"""
        SELECT ca.name, cv.value
        FROM configuration_value cv
        JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id
        WHERE cv.configuration_id = {config_id}
        """
        rows = db_query(query)
        if rows:
            for row in rows.split('\n'):
                parts = row.split('\t')
                if len(parts) >= 2:
                    attributes[parts[0]] = parts[1]

# 3. Safe fallback check: Check if the exact token exists ANYWHERE in configuration_value
exact_match_count_str = db_query(f"SELECT COUNT(*) FROM configuration_value WHERE value = '{target_suffix}'")
exact_match_count = int(exact_match_count_str) if exact_match_count_str and exact_match_count_str.isdigit() else 0

# 4. Check if Firefox is still running (basic health check)
firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'config_exists': config_exists,
    'node_id': node_id_str if config_exists else None,
    'attributes': attributes,
    'exact_match_count': exact_match_count,
    'firefox_running': firefox_running,
}

# Write out result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported JSON Result:")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="