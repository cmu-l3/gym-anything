#!/bin/bash
# Export script for pod_lifecycle_governance task
# Retrieves the full JSON specs of the modified deployments to be verified programmatically

echo "=== Exporting pod_lifecycle_governance result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final state screenshot
take_screenshot /tmp/pod_lifecycle_governance_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/pod_lifecycle_governance_start_ts 2>/dev/null || echo "0")

# ── Retrieve full Deployments JSON ──────────────────────────────────────────
echo "Fetching deployments from core-system..."
DEPS_JSON=$(docker exec rancher kubectl get deployments -n core-system -o json 2>/dev/null || echo '{"items":[]}')

# Fallback if command fails completely to avoid invalid JSON output
if [ -z "$DEPS_JSON" ] || [ "$DEPS_JSON" = "null" ]; then
    DEPS_JSON='{"items":[]}'
fi

# ── Count running pods for each deployment ──────────────────────────────────
# This ensures the agent didn't introduce syntax errors that prevent pods from starting
echo "Checking running pod counts..."

PUBLIC_API_PODS=$(docker exec rancher kubectl get pods -n core-system -l app=public-api --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
REPORT_GEN_PODS=$(docker exec rancher kubectl get pods -n core-system -l app=report-generator --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
CACHE_NODE_PODS=$(docker exec rancher kubectl get pods -n core-system -l app=cache-node --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")

[ -z "$PUBLIC_API_PODS" ] && PUBLIC_API_PODS=0
[ -z "$REPORT_GEN_PODS" ] && REPORT_GEN_PODS=0
[ -z "$CACHE_NODE_PODS" ] && CACHE_NODE_PODS=0

# ── Write result JSON safely ────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "task_start": $TASK_START,
  "deployments": $DEPS_JSON,
  "running_pods": {
    "public-api": $PUBLIC_API_PODS,
    "report-generator": $REPORT_GEN_PODS,
    "cache-node": $CACHE_NODE_PODS
  }
}
EOF

# Move to final location with proper permissions
rm -f /tmp/pod_lifecycle_governance_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/pod_lifecycle_governance_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/pod_lifecycle_governance_result.json
chmod 666 /tmp/pod_lifecycle_governance_result.json 2>/dev/null || sudo chmod 666 /tmp/pod_lifecycle_governance_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/pod_lifecycle_governance_result.json"
echo "=== Export Complete ==="