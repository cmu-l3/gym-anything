#!/bin/bash
# Export script for pvc_data_migration_workflow

echo "=== Exporting pvc_data_migration_workflow result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/pvc_data_migration_final.png 2>/dev/null || true

# ── 1. Check PVC status ───────────────────────────────────────────────────────
PVC_JSON=$(docker exec rancher kubectl get pvc -n catalog -o json 2>/dev/null || echo '{"items":[]}')

# ── 2. Check Deployment status ────────────────────────────────────────────────
DEPLOY_JSON=$(docker exec rancher kubectl get deployment catalog-service -n catalog -o json 2>/dev/null || echo '{}')

# ── 3. Check Pods status ──────────────────────────────────────────────────────
PODS_JSON=$(docker exec rancher kubectl get pods -n catalog -l app=catalog-service -o json 2>/dev/null || echo '{"items":[]}')

# Find a running pod to check data integrity
RUNNING_POD=$(docker exec rancher kubectl get pods -n catalog -l app=catalog-service --field-selector status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

CHINOOK_MD5=""
META_MD5=""

if [ -n "$RUNNING_POD" ]; then
    # Execute md5sum inside the pod
    CHINOOK_MD5=$(docker exec rancher kubectl exec -n catalog "$RUNNING_POD" -- md5sum /usr/share/nginx/html/data/chinook.db 2>/dev/null | awk '{print $1}')
    META_MD5=$(docker exec rancher kubectl exec -n catalog "$RUNNING_POD" -- md5sum /usr/share/nginx/html/data/catalog-metadata.json 2>/dev/null | awk '{print $1}')
fi

# ── Export JSON ───────────────────────────────────────────────────────────────
export PVC_JSON DEPLOY_JSON PODS_JSON CHINOOK_MD5 META_MD5

python3 << 'PYEOF'
import json
import os

def parse_json(s):
    try:
        return json.loads(s)
    except Exception:
        return {}

pvc_data = parse_json(os.environ.get("PVC_JSON", "{}"))
deploy_data = parse_json(os.environ.get("DEPLOY_JSON", "{}"))
pods_data = parse_json(os.environ.get("PODS_JSON", "{}"))

result = {
    "pvcs": pvc_data.get("items", []),
    "deployment": deploy_data,
    "pods": pods_data.get("items", []),
    "running_pod_found": bool(os.environ.get("RUNNING_POD")),
    "data_hashes": {
        "chinook": os.environ.get("CHINOOK_MD5", "").strip(),
        "metadata": os.environ.get("META_MD5", "").strip()
    }
}

with open("/tmp/pvc_data_migration_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written to /tmp/pvc_data_migration_result.json"
echo "=== Export Complete ==="