#!/system/bin/sh
echo "=== Exporting configure_scooter_routing results ==="

PACKAGE="com.sygic.aura"
TASK_DIR="/sdcard/tasks/configure_scooter_routing"
PREFS_DIR="/data/data/$PACKAGE/shared_prefs"

# 1. Capture final screenshot
screencap -p "$TASK_DIR/task_final.png"

# 2. Dump UI Hierarchy (for XML verification fallback)
uiautomator dump "$TASK_DIR/ui_dump.xml"

# 3. Snapshot final preferences
mkdir -p "$TASK_DIR/artifacts/final"
if [ -d "$PREFS_DIR" ]; then
    su 0 cp -r "$PREFS_DIR/." "$TASK_DIR/artifacts/final/" 2>/dev/null
    chmod -R 777 "$TASK_DIR/artifacts/final" 2>/dev/null
fi

# 4. Create result manifest
# We create a simple JSON. Note: Android shell usually doesn't have 'jq', 
# so we construct it manually.

START_TIME=$(cat "$TASK_DIR/task_start_time.txt" 2>/dev/null || echo "0")
END_TIME=$(date +%s)
SCREENSHOT_EXISTS=$([ -f "$TASK_DIR/task_final.png" ] && echo "true" || echo "false")

echo "{" > "$TASK_DIR/task_result.json"
echo "  \"task_start\": $START_TIME," >> "$TASK_DIR/task_result.json"
echo "  \"task_end\": $END_TIME," >> "$TASK_DIR/task_result.json"
echo "  \"screenshot_exists\": $SCREENSHOT_EXISTS," >> "$TASK_DIR/task_result.json"
echo "  \"screenshot_path\": \"$TASK_DIR/task_final.png\"," >> "$TASK_DIR/task_result.json"
echo "  \"prefs_snapshot_initial\": \"$TASK_DIR/artifacts/initial\"," >> "$TASK_DIR/task_result.json"
echo "  \"prefs_snapshot_final\": \"$TASK_DIR/artifacts/final\"" >> "$TASK_DIR/task_result.json"
echo "}" >> "$TASK_DIR/task_result.json"

echo "=== Export complete ==="
cat "$TASK_DIR/task_result.json"