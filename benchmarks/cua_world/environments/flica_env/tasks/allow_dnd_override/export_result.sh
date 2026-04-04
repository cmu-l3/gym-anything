#!/system/bin/sh
echo "=== Exporting DND Override results ==="

TASK_DIR="/sdcard/tasks/allow_dnd_override"
RESULT_JSON="$TASK_DIR/task_result.json"
PACKAGE="com.robert.fcView"

# 1. Get current time
END_TIME=$(date +%s)
START_TIME=$(cat "$TASK_DIR/start_time.txt" 2>/dev/null || echo "0")

# 2. Get Final Zen Mode (0=OFF, 1/2/3=ON)
FINAL_ZEN=$(settings get global zen_mode)

# 3. Get Notification Policy info
# This dump contains the list of apps allowed to bypass DND
POLICY_DUMP=$(dumpsys notification policy 2>/dev/null)

# Check specifically for our package in the allow list
IS_ALLOWED="false"
if echo "$POLICY_DUMP" | grep -q "package=$PACKAGE" || \
   echo "$POLICY_DUMP" | grep -q "allow_dnd $PACKAGE true"; then
    IS_ALLOWED="true"
fi

# Also check via 'cmd notification' if possible, or inspection of dumpsys notification
# Look for 'priority' or 'bypassDnd' flags for the package channels
NOTIF_DUMP=$(dumpsys notification 2>/dev/null)
CHANNEL_BYPASS="false"
if echo "$NOTIF_DUMP" | grep -A 20 "pkg=$PACKAGE" | grep -q "bypassDnd=true"; then
    CHANNEL_BYPASS="true"
fi

# 4. Check Navigation History (Activity Recents)
# Did they actually go to Settings?
RECENTS=$(dumpsys activity recents)
SETTINGS_VISITED="false"
if echo "$RECENTS" | grep -q "com.android.settings"; then
    SETTINGS_VISITED="true"
fi

# 5. Capture final screenshot
screencap -p "$TASK_DIR/final_state.png"

# 6. Construct JSON Result
# We use a temporary file strategy to ensure valid JSON
cat > "$RESULT_JSON" << EOF
{
  "task_start": $START_TIME,
  "task_end": $END_TIME,
  "final_zen_mode": "$FINAL_ZEN",
  "app_allowed_in_policy": $IS_ALLOWED,
  "channel_bypass_dnd": $CHANNEL_BYPASS,
  "settings_visited": $SETTINGS_VISITED,
  "package": "$PACKAGE"
}
EOF

# Append dumps for debugging if needed (not in JSON)
echo "--- Policy Dump excerpt ---" >> "$TASK_DIR/debug_info.txt"
echo "$POLICY_DUMP" | grep -C 5 "$PACKAGE" >> "$TASK_DIR/debug_info.txt" 2>/dev/null || true

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"