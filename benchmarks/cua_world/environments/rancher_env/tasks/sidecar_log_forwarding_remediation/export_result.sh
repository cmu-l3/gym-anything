#!/bin/bash
# Export script for sidecar_log_forwarding_remediation task

echo "=== Exporting sidecar_log_forwarding_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract Deployment JSON
DEPLOYMENT_JSON=$(docker exec rancher kubectl get deployment legacy-payment-worker -n finance-ops -o json 2>/dev/null || echo "{}")

# Extract ConfigMap JSON
CONFIGMAP_JSON=$(docker exec rancher kubectl get configmap fluent-bit-config -n finance-ops -o json 2>/dev/null || echo "{}")

# Extract Sidecar Logs (give it a moment to flush if recently restarted)
sleep 3
LOGS=$(docker exec rancher kubectl logs deployment/legacy-payment-worker -c fluent-bit -n finance-ops --tail=100 2>/dev/null || echo "NO_LOGS")
LOGS_B64=$(echo "$LOGS" | base64 -w 0)

# Create JSON result (use temp file for permission safety)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "deployment": $DEPLOYMENT_JSON,
    "configmap": $CONFIGMAP_JSON,
    "fluent_bit_logs_b64": "$LOGS_B64",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="