#!/bin/bash
echo "=== Exporting customize_home_dashboard results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/customize_dashboard_final.png

# Copy the check script to the app container again to get the final state
docker cp /tmp/check_dashlets.php suitecrm-app:/tmp/check_dashlets.php
docker exec suitecrm-app php /tmp/check_dashlets.php > /tmp/final_dashlets.json 2>/dev/null || echo '{"count": 0, "modules": []}' > /tmp/final_dashlets.json

# Read values
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_JSON=$(cat /tmp/initial_dashlets.json 2>/dev/null || echo '{}')
FINAL_JSON=$(cat /tmp/final_dashlets.json 2>/dev/null || echo '{}')

# Combine into a single result file
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": ${TASK_START},
  "initial_state": ${INITIAL_JSON},
  "final_state": ${FINAL_JSON}
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== customize_home_dashboard export complete ==="