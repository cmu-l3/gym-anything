#!/bin/bash
echo "=== Exporting cicd_rbac_token_provisioning result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Fetching cluster states..."

# 1. Check if the dangerous ClusterRoleBinding still exists
CRB_JSON=$(docker exec rancher kubectl get clusterrolebinding github-actions-admin -o json 2>/dev/null || echo "{}")

# 2. Check if the Role 'cicd-deployer' exists in 'webapp'
ROLE_JSON=$(docker exec rancher kubectl get role cicd-deployer -n webapp -o json 2>/dev/null || echo "{}")

# 3. Check if the RoleBinding 'cicd-deployer-binding' exists in 'webapp'
RB_JSON=$(docker exec rancher kubectl get rolebinding cicd-deployer-binding -n webapp -o json 2>/dev/null || echo "{}")

# 4. Check if the Secret 'github-actions-token' exists in 'webapp'
SECRET_JSON=$(docker exec rancher kubectl get secret github-actions-token -n webapp -o json 2>/dev/null || echo "{}")

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "task_start": $TASK_START,
  "crb": $CRB_JSON,
  "role": $ROLE_JSON,
  "rb": $RB_JSON,
  "secret": $SECRET_JSON
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
echo "=== Export Complete ==="