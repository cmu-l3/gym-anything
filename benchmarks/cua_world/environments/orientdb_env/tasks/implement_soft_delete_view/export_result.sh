#!/bin/bash
echo "=== Exporting implement_soft_delete_view results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query Schema to check for Property
echo "Querying schema..."
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

# 2. Query Data to check tagging (IsHidden values)
echo "Querying marker data..."
# Check Toxic Marker (should be true)
TOXIC_DATA=$(orientdb_sql "demodb" "SELECT IsHidden FROM Reviews WHERE Text='MARKER_TOXIC_REVIEW'")
# Check Good Marker (should be false or null)
GOOD_DATA=$(orientdb_sql "demodb" "SELECT IsHidden FROM Reviews WHERE Text='MARKER_GOOD_REVIEW'")

# 3. Query View to check logic
echo "Querying view..."
# We try to select from the view. If it doesn't exist, this returns an error JSON.
VIEW_DATA=$(orientdb_sql "demodb" "SELECT Text FROM PublicReviews WHERE Text LIKE 'MARKER_%'")

# 4. Check if app is running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 5. Capture final screenshot
take_screenshot /tmp/task_final.png

# 6. Create result JSON
# We embed the raw JSON responses from OrientDB into our result JSON
# Using jq to safely structure the JSON
jq -n \
    --arg start "$TASK_START" \
    --arg end "$TASK_END" \
    --arg app_running "$APP_RUNNING" \
    --argjson schema "$SCHEMA_JSON" \
    --argjson toxic "$TOXIC_DATA" \
    --argjson good "$GOOD_DATA" \
    --argjson view "$VIEW_DATA" \
    '{
        task_start: $start,
        task_end: $end,
        app_was_running: $app_running,
        schema_snapshot: $schema,
        marker_toxic: $toxic,
        marker_good: $good,
        view_result: $view
    }' > /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="