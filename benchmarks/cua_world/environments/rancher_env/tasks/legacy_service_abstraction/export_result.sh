#!/bin/bash
# Export script for legacy_service_abstraction task
# Queries the retail-system namespace for the refactored services and configuration

echo "=== Exporting legacy_service_abstraction result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/legacy_service_abstraction_start_ts 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Retrieving cluster states..."

# 1. Get legacy-oracle Service JSON
SVC_LEGACY_ORACLE=$(docker exec rancher kubectl get svc legacy-oracle -n retail-system -o json 2>/dev/null || echo '{}')

# 2. Get legacy-oracle Endpoints JSON
EP_LEGACY_ORACLE=$(docker exec rancher kubectl get endpoints legacy-oracle -n retail-system -o json 2>/dev/null || echo '{}')

# 3. Get stripe-api Service JSON
SVC_STRIPE=$(docker exec rancher kubectl get svc stripe-api -n retail-system -o json 2>/dev/null || echo '{}')

# 4. Get ConfigMap JSON
CM_CONFIG=$(docker exec rancher kubectl get cm inventory-api-config -n retail-system -o json 2>/dev/null || echo '{}')

# 5. Get live pod environment variables (to verify rollout restart)
POD_NAME=$(docker exec rancher kubectl get pod -n retail-system -l app=inventory-api --field-selector status.phase=Running -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo "")

POD_ENV=""
if [ -n "$POD_NAME" ]; then
    POD_ENV=$(docker exec rancher kubectl exec -n retail-system "$POD_NAME" -- env | grep ORACLE_DB_URL 2>/dev/null || echo "")
fi

# Write results to a structured JSON file using python to ensure valid escaping
export SVC_LEGACY_ORACLE
export EP_LEGACY_ORACLE
export SVC_STRIPE
export CM_CONFIG
export POD_ENV
export TASK_START
export TASK_END

python3 << 'PYEOF'
import os
import json

def parse_json_env(var_name):
    val = os.environ.get(var_name, "{}")
    try:
        return json.loads(val)
    except:
        return {}

result = {
    "task_start": int(os.environ.get("TASK_START", "0")),
    "task_end": int(os.environ.get("TASK_END", "0")),
    "svc_legacy_oracle": parse_json_env("SVC_LEGACY_ORACLE"),
    "ep_legacy_oracle": parse_json_env("EP_LEGACY_ORACLE"),
    "svc_stripe": parse_json_env("SVC_STRIPE"),
    "cm_config": parse_json_env("CM_CONFIG"),
    "pod_env_oracle_url": os.environ.get("POD_ENV", "")
}

with open("/tmp/legacy_service_abstraction_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written to /tmp/legacy_service_abstraction_result.json"
echo "=== Export Complete ==="