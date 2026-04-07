#!/bin/bash
echo "=== Exporting crd_schema_evolution_validation result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Fetch the CRD configuration
echo "Fetching CRD definition..."
CRD_JSON=$(docker exec rancher kubectl get crd databases.platform.local -o json 2>/dev/null || echo "{}")

# Fetch the Custom Resource
echo "Fetching billing-db Custom Resource..."
CR_JSON=$(docker exec rancher kubectl get database billing-db -n default -o json 2>/dev/null || echo "{}")

# Check if app is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Assemble into a single result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "crd": $CRD_JSON,
    "custom_resource": $CR_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/crd_task_result.json 2>/dev/null || sudo rm -f /tmp/crd_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/crd_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/crd_task_result.json
chmod 666 /tmp/crd_task_result.json 2>/dev/null || sudo chmod 666 /tmp/crd_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/crd_task_result.json"
echo "=== Export complete ==="