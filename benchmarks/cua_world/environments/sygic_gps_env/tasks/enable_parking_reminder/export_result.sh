#!/system/bin/sh
# Export script for enable_parking_reminder task

echo "=== Exporting Task Results ==="

PACKAGE="com.sygic.aura"
TASK_DIR="/sdcard/tasks/enable_parking_reminder"
RESULT_JSON="$TASK_DIR/task_result.json"

# 1. Capture Final Screenshot
screencap -p "$TASK_DIR/final_state.png"

# 2. Check App Status
APP_RUNNING=$(pgrep -f "com.sygic.aura" > /dev/null && echo "true" || echo "false")

# 3. Snapshot Final Preferences
echo "Snapshotting final preferences..."
PREFS_DIR="/data/data/$PACKAGE/shared_prefs"
rm -rf "$TASK_DIR/final_prefs"
su 0 cp -r "$PREFS_DIR" "$TASK_DIR/final_prefs" 2>/dev/null || true
chmod -R 777 "$TASK_DIR/final_prefs" 2>/dev/null || true

# Extract parking lines
grep -r -i "park" "$TASK_DIR/final_prefs" > "$TASK_DIR/final_parking_state.txt" 2>/dev/null || echo "" > "$TASK_DIR/final_parking_state.txt"

# 4. Compare States (Determine if changed)
# We read files into variables to compare content
INITIAL_CONTENT=$(cat "$TASK_DIR/initial_parking_state.txt")
FINAL_CONTENT=$(cat "$TASK_DIR/final_parking_state.txt")

PREFS_CHANGED="false"
if [ "$INITIAL_CONTENT" != "$FINAL_CONTENT" ]; then
    PREFS_CHANGED="true"
fi

# 5. Determine Current Value (Heuristic)
# Look for "true" or "1" associated with parking in the final dump
IS_ENABLED="false"
if echo "$FINAL_CONTENT" | grep -iE "park.*(true|1|\"value\":1)" > /dev/null; then
    IS_ENABLED="true"
fi

# 6. Construct JSON Result
cat > "$RESULT_JSON" <<EOF
{
  "app_running": $APP_RUNNING,
  "prefs_changed": $PREFS_CHANGED,
  "parking_feature_enabled": $IS_ENABLED,
  "initial_prefs_dump": "$(echo "$INITIAL_CONTENT" | tr -d '\n' | sed 's/"/\\"/g')",
  "final_prefs_dump": "$(echo "$FINAL_CONTENT" | tr -d '\n' | sed 's/"/\\"/g')",
  "screenshot_path": "$TASK_DIR/final_state.png"
}
EOF

# Ensure permissions for host to read
chmod 666 "$RESULT_JSON" 2>/dev/null

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"