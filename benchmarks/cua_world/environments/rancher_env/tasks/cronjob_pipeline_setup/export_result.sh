#!/bin/bash
# Export script for cronjob_pipeline_setup task

echo "=== Exporting cronjob_pipeline_setup result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# ── Fetch all CronJobs in operations namespace ────────────────────────────────
CRONJOBS_JSON=$(docker exec rancher kubectl get cronjobs -n operations -o json 2>/dev/null || echo '{"items":[]}')

# Use a temporary file to safely write JSON
TEMP_JSON=$(mktemp /tmp/cronjob_pipeline_result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "cronjobs": $CRONJOBS_JSON
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/cronjob_pipeline_result.json 2>/dev/null || sudo rm -f /tmp/cronjob_pipeline_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/cronjob_pipeline_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/cronjob_pipeline_result.json
chmod 666 /tmp/cronjob_pipeline_result.json 2>/dev/null || sudo chmod 666 /tmp/cronjob_pipeline_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/cronjob_pipeline_result.json"
echo "=== Export complete ==="