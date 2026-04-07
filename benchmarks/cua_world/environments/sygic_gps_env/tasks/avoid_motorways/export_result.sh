#!/system/bin/sh
echo "=== Exporting avoid_motorways results ==="

PACKAGE="com.sygic.aura"
DATA_DIR="/sdcard/task_data"

# Record end time
date +%s > "$DATA_DIR/task_end_time.txt"

# 1. Capture FINAL state of shared preferences
echo "Capturing final preferences state..."
mkdir -p "$DATA_DIR/final_prefs"
cp -r /data/data/$PACKAGE/shared_prefs/* "$DATA_DIR/final_prefs/" 2>/dev/null
if [ -z "$(ls -A $DATA_DIR/final_prefs)" ]; then
    run-as $PACKAGE cp -r /data/data/$PACKAGE/shared_prefs/* "$DATA_DIR/final_prefs/" 2>/dev/null
fi

# 2. Capture Final Screenshot
echo "Capturing screenshot..."
screencap -p "$DATA_DIR/final_screenshot.png"

# 3. Dump UI Hierarchy (for optional verification text check)
uiautomator dump "$DATA_DIR/final_ui.xml" 2>/dev/null

# 4. Create Result JSON
# We'll build a simple JSON with file existence checks
INITIAL_PREFS_COUNT=$(ls "$DATA_DIR/initial_prefs" 2>/dev/null | wc -l)
FINAL_PREFS_COUNT=$(ls "$DATA_DIR/final_prefs" 2>/dev/null | wc -l)

echo "{" > "$DATA_DIR/result_manifest.json"
echo "  \"timestamp\": $(date +%s)," >> "$DATA_DIR/result_manifest.json"
echo "  \"initial_prefs_count\": $INITIAL_PREFS_COUNT," >> "$DATA_DIR/result_manifest.json"
echo "  \"final_prefs_count\": $FINAL_PREFS_COUNT," >> "$DATA_DIR/result_manifest.json"
echo "  \"screenshot_path\": \"$DATA_DIR/final_screenshot.png\"" >> "$DATA_DIR/result_manifest.json"
echo "}" >> "$DATA_DIR/result_manifest.json"

echo "=== Export complete ==="