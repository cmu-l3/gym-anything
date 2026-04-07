#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting configure_exam_accessibility_features results ==="

# Take final evidence screenshot
take_screenshot /tmp/final_screenshot.png

# Query the database to retrieve actual nested UI states
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

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except Exception:
    start_time = 0.0

exam_name = "ENGL 204: Modernist Literature Final"
# Get the ID of the target configuration
config_id = db_query(f"SELECT id FROM configuration_node WHERE name='{exam_name}' ORDER BY id DESC LIMIT 1")

result = {
    'task_start_time': start_time,
    'export_time': time.time(),
    'config_exists': bool(config_id),
    'config_id': config_id,
    'spell_check': 'false',
    'text_search': 'false',
    'zooming': 'false',
    'changed_timestamp': 0.0
}

# Pull exact values of the configuration attributes if config exists
if config_id:
    # We use LIKE matches as attributes often carry domain prefixes (e.g. "browser.allowSpellCheck")
    spell = db_query(f"SELECT cv.value FROM configuration_value cv JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id WHERE cv.configuration_node_id = {config_id} AND ca.name LIKE '%allowSpellCheck%' LIMIT 1")
    search = db_query(f"SELECT cv.value FROM configuration_value cv JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id WHERE cv.configuration_node_id = {config_id} AND ca.name LIKE '%allowTextSearch%' LIMIT 1")
    zoom = db_query(f"SELECT cv.value FROM configuration_value cv JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id WHERE cv.configuration_node_id = {config_id} AND ca.name LIKE '%enableZooming%' LIMIT 1")
    
    # Check timestamp to confirm save action happened
    changed_ts = db_query(f"SELECT UNIX_TIMESTAMP(changed_date) FROM configuration_node WHERE id = {config_id}")
    
    result['spell_check'] = spell.lower() if spell else 'false'
    result['text_search'] = search.lower() if search else 'false'
    result['zooming'] = zoom.lower() if zoom else 'false'
    result['changed_timestamp'] = float(changed_ts) if changed_ts else 0.0

# Dump state out to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="