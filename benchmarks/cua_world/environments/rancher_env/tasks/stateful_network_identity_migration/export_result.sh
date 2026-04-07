#!/bin/bash
# Export script for stateful_network_identity_migration task

echo "=== Exporting stateful_network_identity_migration result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final state screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# ── Query API for Workload Kinds ─────────────────────────────────────────────
# Check if the bad Deployment still exists
DEPLOYMENT_EXISTS=$(docker exec rancher kubectl get deployment hazelcast-mock -n data-grid --no-headers 2>/dev/null | wc -l | tr -d ' ')

# Check if the StatefulSet was created
STS_EXISTS=$(docker exec rancher kubectl get statefulset hazelcast-mock -n data-grid --no-headers 2>/dev/null | wc -l | tr -d ' ')

# Extract StatefulSet JSON for deeper inspection
STS_JSON=$(docker exec rancher kubectl get statefulset hazelcast-mock -n data-grid -o json 2>/dev/null || echo "{}")

STS_SERVICE_NAME=$(echo "$STS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('spec', {}).get('serviceName', 'none'))
" 2>/dev/null || echo "none")

# ── Query API for Service Configuration ──────────────────────────────────────
# Extract Service JSON
SVC_JSON=$(docker exec rancher kubectl get service hazelcast-discovery -n data-grid -o json 2>/dev/null || echo "{}")

SVC_EXISTS=$(echo "$SVC_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('true' if data.get('metadata', {}).get('name') else 'false')
" 2>/dev/null || echo "false")

SVC_CLUSTER_IP=$(echo "$SVC_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('spec', {}).get('clusterIP', 'unknown'))
" 2>/dev/null || echo "unknown")

# ── Query API for Pod State (Anti-Gaming Runtime Check) ──────────────────────
# Count how many pods for the app are actually Running.
# The container script will immediately exit 1 if the hostname is not sequential.
# Therefore, if pods are Running, the agent successfully deployed a StatefulSet.
RUNNING_PODS=$(docker exec rancher kubectl get pods -n data-grid -l app=hazelcast --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

# Total pods found
TOTAL_PODS=$(docker exec rancher kubectl get pods -n data-grid -l app=hazelcast --no-headers 2>/dev/null | wc -l | tr -d ' ')

# ── Write result JSON ────────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "deployment_count": $DEPLOYMENT_EXISTS,
  "statefulset_count": $STS_EXISTS,
  "sts_service_name": "$STS_SERVICE_NAME",
  "service_exists": $SVC_EXISTS,
  "service_cluster_ip": "$SVC_CLUSTER_IP",
  "running_pods": $RUNNING_PODS,
  "total_pods": $TOTAL_PODS,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/stateful_network_identity_migration_result.json 2>/dev/null || sudo rm -f /tmp/stateful_network_identity_migration_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/stateful_network_identity_migration_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/stateful_network_identity_migration_result.json
chmod 666 /tmp/stateful_network_identity_migration_result.json 2>/dev/null || sudo chmod 666 /tmp/stateful_network_identity_migration_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/stateful_network_identity_migration_result.json"
cat /tmp/stateful_network_identity_migration_result.json
echo "=== Export complete ==="