#!/bin/bash
# Export script for legacy_sidecar_logging_architecture task

echo "=== Exporting legacy_sidecar_logging_architecture result ==="

# Fallback to importing scrot directly if task_utils doesn't exist
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/legacy_sidecar_logging_end.png ga
else
    DISPLAY=:1 scrot /tmp/legacy_sidecar_logging_end.png 2>/dev/null || true
fi

TASK_START=$(cat /tmp/legacy_sidecar_logging_start_ts 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ── 1. Get the Deployment JSON ───────────────────────────────────────────────
DEPLOYMENT_JSON=$(docker exec rancher kubectl get deployment inventory-system -n legacy-ops -o json 2>/dev/null || echo '{}')

# ── 2. Identify a Running Pod and extract logs ───────────────────────────────
PODS_JSON=$(docker exec rancher kubectl get pods -n legacy-ops -l app=inventory-system -o json 2>/dev/null || echo '{"items":[]}')

POD_NAME=$(echo "$PODS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for item in data.get('items', []):
        if item.get('status', {}).get('phase') == 'Running':
            print(item['metadata']['name'])
            sys.exit(0)
except Exception:
    pass
print('')
" 2>/dev/null)

ACCESS_LOGS=""
ERROR_LOGS=""

if [ -n "$POD_NAME" ]; then
    echo "Found Running pod: $POD_NAME"
    # Attempt to grab logs from the expected sidecar containers
    ACCESS_LOGS=$(docker exec rancher kubectl logs "$POD_NAME" -c access-logger --tail 50 2>/dev/null || echo "")
    ERROR_LOGS=$(docker exec rancher kubectl logs "$POD_NAME" -c error-logger --tail 50 2>/dev/null || echo "")
else
    echo "No Running pod found for inventory-system."
fi

# Escape logs for JSON safety
ACCESS_LOGS_ESCAPED=$(echo "$ACCESS_LOGS" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')
ERROR_LOGS_ESCAPED=$(echo "$ERROR_LOGS" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')
DEPLOYMENT_ESCAPED=$(echo "$DEPLOYMENT_JSON" | python3 -c 'import sys, json; print(json.dumps(json.loads(sys.stdin.read())))' 2>/dev/null || echo '"{}"')

# ── Write result JSON ────────────────────────────────────────────────────────
cat > /tmp/legacy_sidecar_logging_result.json <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "deployment": $DEPLOYMENT_ESCAPED,
  "running_pod_name": "$POD_NAME",
  "access_logs": $ACCESS_LOGS_ESCAPED,
  "error_logs": $ERROR_LOGS_ESCAPED
}
EOF

echo "Result JSON written to /tmp/legacy_sidecar_logging_result.json"
echo "=== Export Complete ==="