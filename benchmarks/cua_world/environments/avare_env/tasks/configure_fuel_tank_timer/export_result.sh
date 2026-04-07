#!/system/bin/sh
# Export script for configure_fuel_tank_timer task

echo "=== Exporting results ==="

# 1. Capture Final Screenshot (Critical for VLM)
screencap -p /sdcard/task_final.png

# 2. Export Preferences file (Critical for programmatic check)
# Avare stores settings in /data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml
# We need to copy this to /sdcard/ so the host can read it (requires root/run-as)

PREF_SRC="/data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml"
PREF_DST="/sdcard/avare_preferences.xml"

# Try copying as root (standard in this env)
cp "$PREF_SRC" "$PREF_DST" 2>/dev/null || \
    run-as com.ds.avare cp "$PREF_SRC" "$PREF_DST" 2>/dev/null || \
    cat "$PREF_SRC" > "$PREF_DST" 2>/dev/null

if [ -f "$PREF_DST" ]; then
    echo "Preferences file exported successfully."
    chmod 666 "$PREF_DST"
else
    echo "WARNING: Could not export preferences file."
fi

# 3. Create Result JSON
# We'll create a simple JSON with timestamps and file existence checks
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)
PREF_EXISTS=$([ -f "$PREF_DST" ] && echo "true" || echo "false")

cat > /sdcard/task_result.json <<EOF
{
  "task_start": $START_TIME,
  "task_end": $END_TIME,
  "prefs_exported": $PREF_EXISTS,
  "screenshot_path": "/sdcard/task_final.png",
  "prefs_path": "/sdcard/avare_preferences.xml"
}
EOF

echo "=== Export complete ==="