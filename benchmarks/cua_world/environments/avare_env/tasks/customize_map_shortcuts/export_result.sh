#!/system/bin/sh
echo "=== Exporting customize_map_shortcuts results ==="

PACKAGE="com.ds.avare"
PREFS_SOURCE="/data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml"
EXPORT_DIR="/sdcard/task_export"

mkdir -p "$EXPORT_DIR"

# 1. Capture Final Screenshot (Evidence of visible buttons)
screencap -p "$EXPORT_DIR/task_final.png"
echo "Screenshot captured."

# 2. Stop the app to ensure SharedPreferences are flushed to disk
am force-stop $PACKAGE
sleep 2

# 3. Export SharedPreferences for Verification
# We use 'cat' to copy to avoid permission issues if cp fails across boundaries,
# though on emulator root is usually available.
if [ -f "$PREFS_SOURCE" ]; then
    cat "$PREFS_SOURCE" > "$EXPORT_DIR/preferences.xml"
    chmod 666 "$EXPORT_DIR/preferences.xml"
    echo "Preferences exported."
else
    echo "ERROR: Preferences file not found at $PREFS_SOURCE"
    echo "<map />" > "$EXPORT_DIR/preferences.xml"
fi

# 4. Export Metadata
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create a simple JSON-like structure (Android shell has limited JSON tools)
echo "{" > "$EXPORT_DIR/result_meta.json"
echo "  \"task_start\": $TASK_START," >> "$EXPORT_DIR/result_meta.json"
echo "  \"task_end\": $TASK_END," >> "$EXPORT_DIR/result_meta.json"
echo "  \"package\": \"$PACKAGE\"" >> "$EXPORT_DIR/result_meta.json"
echo "}" >> "$EXPORT_DIR/result_meta.json"

echo "=== Export Complete ==="