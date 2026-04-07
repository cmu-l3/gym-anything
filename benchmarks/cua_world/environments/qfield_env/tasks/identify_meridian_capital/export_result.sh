#!/system/bin/sh
echo "=== Exporting identify_meridian_capital results ==="

TASK_DIR="/sdcard/tasks/identify_meridian_capital"
GPKG_PATH="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
RESULT_JSON="$TASK_DIR/task_result.json"

# 1. Get Timestamps
START_TIME=$(cat "$TASK_DIR/start_time.txt" 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# 2. Get Initial State
INITIAL_COUNT=$(cat "$TASK_DIR/initial_count.txt" 2>/dev/null || echo "0")

# 3. Query Final State
# Check if feature exists
FEATURE_QUERY="SELECT name, description FROM field_observations WHERE name='Ground_Station_25E';"
FEATURE_RESULT=$(sqlite3 "$GPKG_PATH" "$FEATURE_QUERY" 2>/dev/null || echo "")

# Check final count
FINAL_COUNT=$(sqlite3 "$GPKG_PATH" "SELECT COUNT(*) FROM field_observations;" 2>/dev/null || echo "0")

# Check if feature was created (count increased)
COUNT_DIFF=$((FINAL_COUNT - INITIAL_COUNT))

# Get Ground Truth (read from setup file)
GROUND_TRUTH_RAW=$(cat "$TASK_DIR/ground_truth.txt" 2>/dev/null || echo "")
GT_NAME=$(echo "$GROUND_TRUTH_RAW" | cut -d'|' -f1)
GT_LON=$(echo "$GROUND_TRUTH_RAW" | cut -d'|' -f2)

# Parse Agent Result
AGENT_NAME=""
AGENT_DESC=""
if [ -n "$FEATURE_RESULT" ]; then
    AGENT_NAME=$(echo "$FEATURE_RESULT" | cut -d'|' -f1)
    AGENT_DESC=$(echo "$FEATURE_RESULT" | cut -d'|' -f2)
fi

# 4. Construct JSON
# We construct the JSON manually using echo since jq might not be available on Android
echo "{" > "$RESULT_JSON"
echo "  \"timestamp_start\": $START_TIME," >> "$RESULT_JSON"
echo "  \"timestamp_end\": $END_TIME," >> "$RESULT_JSON"
echo "  \"initial_count\": $INITIAL_COUNT," >> "$RESULT_JSON"
echo "  \"final_count\": $FINAL_COUNT," >> "$RESULT_JSON"
echo "  \"count_diff\": $COUNT_DIFF," >> "$RESULT_JSON"
echo "  \"ground_truth_city\": \"$GT_NAME\"," >> "$RESULT_JSON"
echo "  \"ground_truth_lon\": \"$GT_LON\"," >> "$RESULT_JSON"
echo "  \"agent_feature_found\": $([ -n "$FEATURE_RESULT" ] && echo "true" || echo "false")," >> "$RESULT_JSON"
echo "  \"agent_feature_name\": \"$AGENT_NAME\"," >> "$RESULT_JSON"
echo "  \"agent_feature_desc\": \"$AGENT_DESC\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

# 5. Capture Final Screenshot
screencap -p "$TASK_DIR/final_screenshot.png"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="