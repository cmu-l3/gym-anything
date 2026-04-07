#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting configure_language_spellcheck results ==="

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to query the MariaDB database safely and format as JSON
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

# 1. Check if the Exam Configuration node was created
node_id = db_query(
    "SELECT id FROM configuration_node WHERE name='French 305 Midterm' AND type='EXAM_CONFIG' ORDER BY id DESC LIMIT 1"
)

attributes = {}
# 2. Extract configuration attributes linked to this specific node
if node_id:
    # Try to find the linked seb_client_configuration
    seb_config_id = db_query(f"SELECT id FROM seb_client_configuration WHERE configuration_node_id={node_id} ORDER BY id DESC LIMIT 1")
    
    if seb_config_id:
        attr_rows = db_query(f"SELECT `key`, `value` FROM configuration_attribute WHERE seb_client_configuration_id={seb_config_id}")
        if attr_rows:
            for row in attr_rows.split('\n'):
                if '\t' in row:
                    k, v = row.split('\t', 1)
                    attributes[k.strip()] = v.strip()

# 3. Fallback: Grab the most recent configuration attributes across the whole database
# This ensures we can verify the agent's work even if the schema linking logic above misses it.
fallback_attrs = {}
attr_rows_all = db_query(
    "SELECT `key`, `value` FROM configuration_attribute "
    "WHERE `key` IN ('allowSpellCheck', 'allowGrammarCheck', 'allowDictionaryLookup', 'allowDictionarySearch', 'mainBrowserLanguage') "
    "ORDER BY id DESC LIMIT 50"
)
if attr_rows_all:
    for row in attr_rows_all.split('\n'):
        if '\t' in row:
            k, v = row.split('\t', 1)
            k = k.strip()
            # Only store the most recent one (since ORDER BY id DESC)
            if k not in fallback_attrs:
                fallback_attrs[k] = v.strip()

# 4. Check if Firefox is still running
firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    'exam_config_created': bool(node_id),
    'node_id': node_id,
    'attributes_found': len(attributes) > 0,
    'attributes': attributes,
    'fallback_attributes': fallback_attrs,
    'firefox_running': firefox_running,
}

# Write output safely
with open('/tmp/configure_language_spellcheck_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions allow framework to read the file
chmod 666 /tmp/configure_language_spellcheck_result.json 2>/dev/null || sudo chmod 666 /tmp/configure_language_spellcheck_result.json 2>/dev/null || true

echo "=== Export complete ==="