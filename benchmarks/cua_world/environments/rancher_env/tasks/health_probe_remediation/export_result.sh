#!/bin/bash
# Export script for health_probe_remediation task

echo "=== Exporting health_probe_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/health_probe_remediation_end.png

# Export data via Kubernetes API
echo "Fetching deployment configurations..."
docker exec rancher kubectl get deploy api-server -n services -o json 2>/dev/null > /tmp/api.json || echo "{}" > /tmp/api.json
docker exec rancher kubectl get deploy worker-service -n services -o json 2>/dev/null > /tmp/worker.json || echo "{}" > /tmp/worker.json
docker exec rancher kubectl get deploy auth-service -n services -o json 2>/dev/null > /tmp/auth.json || echo "{}" > /tmp/auth.json
docker exec rancher kubectl get deploy notification-service -n services -o json 2>/dev/null > /tmp/notif.json || echo "{}" > /tmp/notif.json

echo "Fetching pod statuses..."
docker exec rancher kubectl get pods -n services -o json 2>/dev/null > /tmp/pods.json || echo '{"items":[]}' > /tmp/pods.json

# Build a comprehensive result JSON using Python to avoid bash escaping issues
python3 -c '
import json
import os

def load_j(f):
    try:
        with open(f, "r") as file:
            return json.load(file)
    except Exception:
        return {}

result = {
    "api_server": load_j("/tmp/api.json"),
    "worker_service": load_j("/tmp/worker.json"),
    "auth_service": load_j("/tmp/auth.json"),
    "notification_service": load_j("/tmp/notif.json"),
    "pods": load_j("/tmp/pods.json")
}

with open("/tmp/health_probe_remediation_result.json", "w") as out:
    json.dump(result, out, indent=2)
'

chmod 666 /tmp/health_probe_remediation_result.json

echo "Result JSON written to /tmp/health_probe_remediation_result.json"
echo "=== Export Complete ==="