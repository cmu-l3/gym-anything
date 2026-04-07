#!/bin/bash
echo "=== Exporting whisper_namespace_migration result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/whisper_namespace_migration_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/whisper_namespace_migration_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/whisper_namespace_migration_start_ts 2>/dev/null || echo "0")

# Prepare a Python script to execute inside the Graphite container
# This script will inspect the filesystem directly, query the index, and extract dashboards.
rm -f /tmp/whisper_export.py 2>/dev/null || true

cat > /tmp/whisper_export.py << 'PYSCRIPT'
import os
import json
import urllib.request
import sqlite3

base_whisper = '/opt/graphite/storage/whisper'
servers = os.path.join(base_whisper, 'servers')
infra_compute = os.path.join(base_whisper, 'infrastructure', 'compute')
infra_network = os.path.join(base_whisper, 'infrastructure', 'network')

state = {
    "compute_migrated": False,
    "network_migrated": False,
    "legacy_removed": True,
    "index_updated": False,
    "dashboards": {}
}

# 1. Check if compute paths are successfully migrated
if os.path.isdir(os.path.join(infra_compute, 'ec2_instance_1')) and \
   os.path.isdir(os.path.join(infra_compute, 'ec2_instance_2')):
    state['compute_migrated'] = True

# 2. Check if network paths are successfully migrated
if os.path.isdir(os.path.join(infra_network, 'load_balancer')):
    state['network_migrated'] = True

# 3. Check if legacy paths were removed
if os.path.exists(os.path.join(servers, 'ec2_instance_1')) or \
   os.path.exists(os.path.join(servers, 'load_balancer')):
    state['legacy_removed'] = False

# 4. Check if index was updated to discover the new namespace
try:
    with urllib.request.urlopen("http://localhost/metrics/index.json", timeout=5) as url:
        index_data = json.loads(url.read().decode())
        has_infra = any(m.startswith('infrastructure.') for m in index_data)
        state['index_updated'] = has_infra
except Exception as e:
    state['index_error'] = str(e)

# 5. Extract dashboard definitions from SQLite
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='dashboard_dashboard'")
    if cursor.fetchone():
        cursor.execute('SELECT name, state FROM dashboard_dashboard')
        for name, s in cursor.fetchall():
            try:
                state['dashboards'][name] = json.loads(s)
            except Exception:
                pass
    conn.close()
except Exception as e:
    state['db_error'] = str(e)

with open('/tmp/namespace_state.json', 'w') as f:
    json.dump(state, f)
PYSCRIPT

# Copy the script into the container, execute it, and extract the state payload
docker cp /tmp/whisper_export.py graphite:/tmp/whisper_export.py 2>/dev/null
docker exec graphite python3 /tmp/whisper_export.py 2>&1
docker cp graphite:/tmp/namespace_state.json /tmp/whisper_namespace_migration_result.json 2>/dev/null || true

# Ensure proper permissions so the framework can read the result file
chmod 666 /tmp/whisper_namespace_migration_result.json 2>/dev/null || true

echo "Result payload generated:"
cat /tmp/whisper_namespace_migration_result.json 2>/dev/null || echo "Payload extraction failed"

echo "=== Export complete ==="