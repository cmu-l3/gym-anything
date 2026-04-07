#!/bin/bash
# Export script for graceful_shutdown_connection_draining task

echo "=== Exporting graceful_shutdown_connection_draining result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/graceful_shutdown_end.png ga || true

# Collect all Deployments in ecommerce namespace
DEPLOYMENTS_JSON=$(docker exec rancher kubectl get deployments -n ecommerce -o json 2>/dev/null || echo '{"items":[]}')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/graceful_shutdown_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "deployments": $DEPLOYMENTS_JSON,
  "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/graceful_shutdown_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/graceful_shutdown_result.json
chmod 666 /tmp/graceful_shutdown_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/graceful_shutdown_result.json"
echo "=== Export Complete ==="