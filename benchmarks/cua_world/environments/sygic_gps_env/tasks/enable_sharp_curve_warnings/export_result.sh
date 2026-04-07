#!/system/bin/sh
# Export script for enable_sharp_curve_warnings
# Captures final preferences and screenshots.

echo "=== Exporting results ==="

TASK_DIR="/sdcard/tasks/enable_sharp_curve_warnings"
PACKAGE="com.sygic.aura"
PREFS_DIR="/data/data/com.sygic.aura/shared_prefs"

# Ensure task dir exists
mkdir -p "$TASK_DIR"

# 1. Capture Final Screenshot
screencap -p "$TASK_DIR/final_state.png"
echo "Screenshot captured."

# 2. Dump Preferences
# We copy the entire shared_prefs directory to the accessible task dir
# This allows the verifier to scan all XML files for the key
mkdir -p "$TASK_DIR/final_prefs"
if [ -d "$PREFS_DIR" ]; then
    cp -r "$PREFS_DIR/"* "$TASK_DIR/final_prefs/"
    chmod -R 666 "$TASK_DIR/final_prefs"
    echo "Preferences dumped."
else
    echo "WARNING: Preferences directory not found."
fi

# 3. Create Result JSON
# We check if the app is running and if files exist
APP_RUNNING=$(pidof "$PACKAGE" > /dev/null && echo "true" || echo "false")
TIMESTAMP=$(date +%s)

cat > "$TASK_DIR/result.json" <<EOF
{
  "timestamp": $TIMESTAMP,
  "app_running": $APP_RUNNING,
  "prefs_exported": true,
  "screenshot_path": "$TASK_DIR/final_state.png"
}
EOF

echo "Result JSON created."
echo "=== Export complete ==="