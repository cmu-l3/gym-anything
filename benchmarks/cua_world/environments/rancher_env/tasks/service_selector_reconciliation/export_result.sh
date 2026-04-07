#!/bin/bash
# Export script for service_selector_reconciliation task

echo "=== Exporting service_selector_reconciliation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Fetch current Endpoints and Deployments as JSON
docker exec rancher kubectl get endpoints -n logistics -o json > /tmp/eps.json 2>/dev/null || echo '{"items":[]}' > /tmp/eps.json
docker exec rancher kubectl get deployments -n logistics -o json > /tmp/deps.json 2>/dev/null || echo '{"items":[]}' > /tmp/deps.json

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to accurately parse the JSON into our unified result file
python3 - << PYEOF > /tmp/service_selector_reconciliation_result.json
import json
import time

def count_ready_addresses(ep_item):
    """Count how many IP addresses are currently ready in an Endpoint subset."""
    count = 0
    for subset in ep_item.get('subsets', []):
        count += len(subset.get('addresses', []))
    return count

try:
    with open('/tmp/eps.json', 'r') as f:
        eps_data = json.load(f)
except Exception:
    eps_data = {'items': []}

try:
    with open('/tmp/deps.json', 'r') as f:
        deps_data = json.load(f)
except Exception:
    deps_data = {'items': []}

endpoints = {item.get('metadata', {}).get('name'): item for item in eps_data.get('items', [])}
deployments = {item.get('metadata', {}).get('name'): item for item in deps_data.get('items', [])}

result = {
    "task_start_time": ${TASK_START},
    "export_time": int(time.time()),
    "services": {},
    "deployments": {}
}

# 1. Order API
ep = endpoints.get('order-api', {})
result["services"]["order-api"] = {"ready_endpoints": count_ready_addresses(ep)}
dep = deployments.get('order-api-deploy', {})
result["deployments"]["order-api-deploy"] = {"ready_replicas": dep.get('status', {}).get('readyReplicas', 0)}

# 2. Tracking Service
ep = endpoints.get('tracking-svc', {})
result["services"]["tracking-svc"] = {"ready_endpoints": count_ready_addresses(ep)}
dep = deployments.get('tracking-deploy', {})
result["deployments"]["tracking-deploy"] = {"ready_replicas": dep.get('status', {}).get('readyReplicas', 0)}

# 3. Inventory Service
ep = endpoints.get('inventory-svc', {})
result["services"]["inventory-svc"] = {"ready_endpoints": count_ready_addresses(ep)}
dep = deployments.get('inventory-deploy', {})
result["deployments"]["inventory-deploy"] = {"ready_replicas": dep.get('status', {}).get('readyReplicas', 0)}

# 4. Notification Hub
ep = endpoints.get('notification-hub', {})
result["services"]["notification-hub"] = {"ready_endpoints": count_ready_addresses(ep)}
dep = deployments.get('notification-deploy', {})
result["deployments"]["notification-deploy"] = {"ready_replicas": dep.get('status', {}).get('readyReplicas', 0)}

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/service_selector_reconciliation_result.json 2>/dev/null || sudo chmod 666 /tmp/service_selector_reconciliation_result.json 2>/dev/null || true

echo "Result JSON written to /tmp/service_selector_reconciliation_result.json"
cat /tmp/service_selector_reconciliation_result.json
echo "=== Export Complete ==="