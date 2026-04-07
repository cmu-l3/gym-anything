#!/system/bin/sh
echo "=== Exporting Amend Flight Plan Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screen state
screencap -p /sdcard/task_final.png

# Search for the exported GPX file
# Avare typically exports to /sdcard/ or /sdcard/Download/
# We look for files modified AFTER task start
echo "Searching for exported GPX files..."

FOUND_GPX=""
LATEST_MOD=0

# Helper to check files in a directory
check_dir() {
    DIR="$1"
    if [ -d "$DIR" ]; then
        for f in "$DIR"/*.gpx; do
            if [ -f "$f" ]; then
                MOD=$(stat -c %Y "$f" 2>/dev/null || echo "0")
                if [ "$MOD" -gt "$TASK_START" ]; then
                    echo "Found candidate: $f (mod: $MOD)"
                    if [ "$MOD" -gt "$LATEST_MOD" ]; then
                        LATEST_MOD=$MOD
                        FOUND_GPX="$f"
                    fi
                fi
            fi
        done
    fi
}

check_dir "/sdcard"
check_dir "/sdcard/Download"
check_dir "/sdcard/Documents"
check_dir "/sdcard/Android/data/com.ds.avare/files"

GPX_EXISTS="false"
GPX_PATH=""

if [ -n "$FOUND_GPX" ]; then
    echo "Selected most recent GPX: $FOUND_GPX"
    GPX_EXISTS="true"
    GPX_PATH="$FOUND_GPX"
    
    # Copy to a standard location for easy retrieval by verifier
    cp "$FOUND_GPX" /sdcard/task_output.gpx
    chmod 666 /sdcard/task_output.gpx
else
    echo "No valid GPX file found created during task window."
fi

# Check if app is running
APP_RUNNING=$(pidof com.ds.avare > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON="/sdcard/task_result_temp.json"
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "gpx_exists": $GPX_EXISTS,
    "original_gpx_path": "$GPX_PATH",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/sdcard/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /sdcard/task_result.json
chmod 666 /sdcard/task_result.json

echo "=== Export Complete ==="