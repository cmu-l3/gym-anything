#!/system/bin/sh
# Export script for perform_emergency_divert
# Captures preferences and screenshots

echo "=== Exporting Task Results ==="

PACKAGE="com.ds.avare"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/${PACKAGE}_preferences.xml"
EXPORT_DIR="/sdcard/task_export"

mkdir -p "$EXPORT_DIR"

# 1. Force stop the app to ensure SharedPreferences are flushed to disk
# Android often keeps prefs in memory; stopping the activity forces a write.
am force-stop $PACKAGE
sleep 2

# 2. Capture final state of preferences
if [ -f "$PREFS_FILE" ]; then
    cp "$PREFS_FILE" "$EXPORT_DIR/final_prefs.xml"
    chmod 666 "$EXPORT_DIR/final_prefs.xml"
    ls -l "$EXPORT_DIR/final_prefs.xml"
else
    echo "ERROR: Preferences file not found at $PREFS_FILE"
fi

# 3. Capture final screenshot (although app is closed now, the trajectory logic handles the visual check. 
# We take one of the desktop just in case, but rely on previous frames for the map view)
screencap -p "$EXPORT_DIR/final_desktop.png"

# 4. Check for state file (Avare sometimes saves state.xml)
if [ -f "/data/data/$PACKAGE/files/state.xml" ]; then
    cp "/data/data/$PACKAGE/files/state.xml" "$EXPORT_DIR/state.xml"
    chmod 666 "$EXPORT_DIR/state.xml"
fi

# 5. Create a simple JSON manifest
echo "{" > "$EXPORT_DIR/result_manifest.json"
echo "  \"timestamp\": $(date +%s)," >> "$EXPORT_DIR/result_manifest.json"
echo "  \"prefs_exported\": true" >> "$EXPORT_DIR/result_manifest.json"
echo "}" >> "$EXPORT_DIR/result_manifest.json"
chmod 666 "$EXPORT_DIR/result_manifest.json"

echo "=== Export Complete ==="