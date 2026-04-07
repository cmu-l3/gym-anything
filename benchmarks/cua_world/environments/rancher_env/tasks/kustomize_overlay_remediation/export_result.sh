#!/bin/bash
# Export script for kustomize_overlay_remediation task
echo "=== Exporting kustomize_overlay_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Determine kubectl command to use
KUBECTL_CMD="kubectl"
if ! command -v kubectl &> /dev/null; then
    KUBECTL_CMD="docker exec rancher kubectl"
fi

# 1. Check if namespace exists
NS_EXISTS=$($KUBECTL_CMD get namespace payment-staging --no-headers 2>/dev/null | wc -l | tr -d ' ')

# 2. Gather resource states from the cluster
DEPLOYMENT_JSON=$($KUBECTL_CMD get deployment payment-gateway -n payment-staging -o json 2>/dev/null || echo '{}')
SERVICE_JSON=$($KUBECTL_CMD get svc payment-gateway -n payment-staging -o json 2>/dev/null || echo '{}')
CONFIGMAP_JSON=$($KUBECTL_CMD get cm payment-config -n payment-staging -o json 2>/dev/null || echo '{}')

# 3. Test the Kustomize build locally to ensure the declarative files are actually fixed
KUSTOMIZE_EXIT_CODE=1
if command -v kubectl &> /dev/null; then
    # Run kustomize and discard stdout, we only care about exit code and validation
    su - ga -c "kubectl kustomize /home/ga/Desktop/payment-gateway/overlays/staging > /dev/null 2>/tmp/kustomize_error.log"
    KUSTOMIZE_EXIT_CODE=$?
fi

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "namespace_exists": $([ "$NS_EXISTS" -gt 0 ] && echo "true" || echo "false"),
  "deployment": $DEPLOYMENT_JSON,
  "service": $SERVICE_JSON,
  "configmap": $CONFIGMAP_JSON,
  "kustomize_exit_code": $KUSTOMIZE_EXIT_CODE
}
EOF

# Move securely
rm -f /tmp/kustomize_overlay_result.json 2>/dev/null || sudo rm -f /tmp/kustomize_overlay_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/kustomize_overlay_result.json
chmod 666 /tmp/kustomize_overlay_result.json
rm -f "$TEMP_JSON"

echo "Results saved to /tmp/kustomize_overlay_result.json"
echo "=== Export Complete ==="