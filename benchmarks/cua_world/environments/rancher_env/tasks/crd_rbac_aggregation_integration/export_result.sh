#!/bin/bash
# Export script for crd_rbac_aggregation_integration task
# This script tests the RBAC by dynamically creating a fresh namespace,
# binding users to the standard aggregated roles, and executing auth matrix queries.

echo "=== Exporting crd_rbac_aggregation_integration result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Give the K8s aggregation controller a few seconds to process any newly added labels
echo "Allowing K8s aggregation controller to settle..."
sleep 5

# ── Setup Dynamic Verification Environment ────────────────────────────────────
# By creating a completely random namespace and fresh service accounts, we
# prevent the agent from gaining points by hardcoding RoleBindings to existing users.
TEST_NS="test-rbac-ns-$RANDOM"
echo "Creating test namespace: $TEST_NS"

docker exec rancher kubectl create namespace "$TEST_NS" >/dev/null

# Create test viewers and editors
docker exec rancher kubectl create serviceaccount test-viewer -n "$TEST_NS" >/dev/null
docker exec rancher kubectl create serviceaccount test-editor -n "$TEST_NS" >/dev/null

# Bind them strictly to the default 'view' and 'edit' ClusterRoles
docker exec rancher kubectl create rolebinding test-viewer-binding \
    --clusterrole=view \
    --serviceaccount="$TEST_NS:test-viewer" \
    -n "$TEST_NS" >/dev/null

docker exec rancher kubectl create rolebinding test-editor-binding \
    --clusterrole=edit \
    --serviceaccount="$TEST_NS:test-editor" \
    -n "$TEST_NS" >/dev/null

# ── Execute K8s Auth Matrix Queries ───────────────────────────────────────────
echo "Executing auth queries..."

# 1. Can the operator update the status?
OP_CAN_UPDATE_STATUS=$(docker exec rancher kubectl auth can-i update datapipelines/status \
    --as=system:serviceaccount:data-system:pipeline-operator -n data-system 2>/dev/null)

# 2. Can the aggregated 'view' role GET datapipelines?
VIEWER_CAN_GET=$(docker exec rancher kubectl auth can-i get datapipelines \
    --as=system:serviceaccount:"$TEST_NS":test-viewer -n "$TEST_NS" 2>/dev/null)

# 3. Can the aggregated 'view' role CREATE datapipelines? (Should be NO)
VIEWER_CAN_CREATE=$(docker exec rancher kubectl auth can-i create datapipelines \
    --as=system:serviceaccount:"$TEST_NS":test-viewer -n "$TEST_NS" 2>/dev/null)

# 4. Can the aggregated 'edit' role CREATE datapipelines?
EDITOR_CAN_CREATE=$(docker exec rancher kubectl auth can-i create datapipelines \
    --as=system:serviceaccount:"$TEST_NS":test-editor -n "$TEST_NS" 2>/dev/null)

# 5. Can the aggregated 'edit' role update STATUS? (Should be NO to respect least privilege)
EDITOR_CAN_UPDATE_STATUS=$(docker exec rancher kubectl auth can-i update datapipelines/status \
    --as=system:serviceaccount:"$TEST_NS":test-editor -n "$TEST_NS" 2>/dev/null)


# ── Clean up dynamic verification environment ─────────────────────────────────
docker exec rancher kubectl delete namespace "$TEST_NS" --wait=false >/dev/null 2>&1

# ── Helper to convert yes/no to true/false for JSON ───────────────────────────
to_bool() {
    if [ "$1" = "yes" ]; then
        echo "true"
    else
        echo "false"
    fi
}

C1_OP_STATUS=$(to_bool "$OP_CAN_UPDATE_STATUS")
C2_VIEW_GET=$(to_bool "$VIEWER_CAN_GET")
C2_VIEW_CREATE=$(to_bool "$VIEWER_CAN_CREATE")
C3_EDIT_CREATE=$(to_bool "$EDITOR_CAN_CREATE")
C4_EDIT_STATUS=$(to_bool "$EDITOR_CAN_UPDATE_STATUS")

# ── Generate JSON Report ──────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
    "operator_can_update_status": $C1_OP_STATUS,
    "viewer_can_get": $C2_VIEW_GET,
    "viewer_can_create": $C2_VIEW_CREATE,
    "editor_can_create": $C3_EDIT_CREATE,
    "editor_can_update_status": $C4_EDIT_STATUS,
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/crd_rbac_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/crd_rbac_result.json
chmod 666 /tmp/crd_rbac_result.json
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/crd_rbac_result.json"
cat /tmp/crd_rbac_result.json

echo "=== Export Complete ==="