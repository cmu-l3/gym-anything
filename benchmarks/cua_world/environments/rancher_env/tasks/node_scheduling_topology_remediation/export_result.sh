#!/bin/bash
# Export script for node_scheduling_topology_remediation task

echo "=== Exporting node_scheduling_topology_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot of the state
take_screenshot /tmp/task_final.png

# Fetch cluster nodes
docker exec rancher kubectl get nodes -o json > /tmp/nodes.json 2>/dev/null || echo '{"items":[]}' > /tmp/nodes.json

# Fetch database deployment
docker exec rancher kubectl get deployment database-primary -n app-prod -o json > /tmp/db_deploy.json 2>/dev/null || echo '{}' > /tmp/db_deploy.json

# Fetch pod statuses
FRONTEND_RUNNING=$(docker exec rancher kubectl get pods -n app-prod -l app=web-frontend --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
DB_RUNNING=$(docker exec rancher kubectl get pods -n app-prod -l app=database-primary --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
BATCH_RUNNING=$(docker exec rancher kubectl get pods -n app-prod -l app=batch-worker --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

[ -z "$FRONTEND_RUNNING" ] && FRONTEND_RUNNING=0
[ -z "$DB_RUNNING" ] && DB_RUNNING=0
[ -z "$BATCH_RUNNING" ] && BATCH_RUNNING=0

# Create JSON output
export FRONTEND_RUNNING DB_RUNNING BATCH_RUNNING

python3 << 'PYEOF'
import json
import os

def load_json(filepath, default):
    try:
        with open(filepath, 'r') as f:
            return json.load(f)
    except Exception:
        return default

nodes_data = load_json('/tmp/nodes.json', {'items': []})
db_data = load_json('/tmp/db_deploy.json', {})

# Evaluate Taints and Labels
nodes = nodes_data.get('items', [])
has_maintenance_taint = False
has_stateful_taint = False
has_batch_label = False

for node in nodes:
    # Check Taints
    taints = node.get('spec', {}).get('taints', [])
    for t in taints:
        if t.get('key') == 'maintenance' and t.get('value') == 'underway' and t.get('effect') == 'NoExecute':
            has_maintenance_taint = True
        if t.get('key') == 'workload-type' and t.get('value') == 'stateful' and t.get('effect') == 'NoSchedule':
            has_stateful_taint = True
    
    # Check Labels
    labels = node.get('metadata', {}).get('labels', {})
    if labels.get('role') == 'batch-processor':
        has_batch_label = True

# Evaluate Database Tolerations
db_tolerations = db_data.get('spec', {}).get('template', {}).get('spec', {}).get('tolerations', [])
db_has_toleration = False

for tol in db_tolerations:
    if tol.get('key') == 'workload-type' and tol.get('value') == 'stateful' and tol.get('effect') == 'NoSchedule':
        db_has_toleration = True
    # Also accept Operator="Exists" for workload-type
    elif tol.get('key') == 'workload-type' and tol.get('operator') == 'Exists':
        db_has_toleration = True

# Prepare result
result = {
    "frontend_running": int(os.environ.get('FRONTEND_RUNNING', 0)),
    "db_running": int(os.environ.get('DB_RUNNING', 0)),
    "batch_running": int(os.environ.get('BATCH_RUNNING', 0)),
    "has_maintenance_taint": has_maintenance_taint,
    "has_stateful_taint": has_stateful_taint,
    "has_batch_label": has_batch_label,
    "db_has_toleration": db_has_toleration
}

with open('/tmp/node_scheduling_topology_remediation_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

echo "Result JSON written to /tmp/node_scheduling_topology_remediation_result.json"
cat /tmp/node_scheduling_topology_remediation_result.json
echo "=== Export Complete ==="