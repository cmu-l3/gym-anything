#!/system/bin/sh
echo "=== Exporting configure_adsb_receiver results ==="

TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Path definitions
PREFS_FILE="/data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml"
EXPORTED_PREFS="/sdcard/final_prefs.xml"
OUTPUT_FILE="/sdcard/adsb_config.txt"
RESULT_JSON="/sdcard/task_result.json"

# 1. Export the internal SharedPreferences file to sdcard for verification
# We need root/su to read from /data/data
if su 0 ls "$PREFS_FILE" >/dev/null 2>&1; then
    echo "Exporting preferences file..."
    su 0 cp "$PREFS_FILE" "$EXPORTED_PREFS"
    su 0 chmod 666 "$EXPORTED_PREFS"
    PREFS_EXISTS="true"
    
    # Get modification time of the actual prefs file
    # Android toybox stat might differ, verifying standard stat behavior
    PREFS_MTIME=$(su 0 stat -c %Y "$PREFS_FILE" 2>/dev/null || echo "0")
else
    echo "Preferences file not found."
    PREFS_EXISTS="false"
    PREFS_MTIME="0"
    rm -f "$EXPORTED_PREFS"
fi

# 2. Check output text file details
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
fi

# 3. Take final screenshot
screencap -p /sdcard/task_final.png

# 4. Construct JSON result
# Note: Using python to generate JSON avoids shell escaping hell
cat > /sdcard/make_json.py << EOF
import json
import time

data = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "prefs_exists": $PREFS_EXISTS,
    "prefs_mtime": $PREFS_MTIME,
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "final_screenshot": "/sdcard/task_final.png"
}

with open("$RESULT_JSON", "w") as f:
    json.dump(data, f)
EOF

python /sdcard/make_json.py
rm /sdcard/make_json.py

echo "Export complete. Result saved to $RESULT_JSON"