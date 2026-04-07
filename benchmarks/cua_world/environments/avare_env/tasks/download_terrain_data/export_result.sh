#!/system/bin/sh
echo "=== Exporting download_terrain_data task ==="

PACKAGE="com.ds.avare"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
DATA_DIR=$(cat /sdcard/avare_data_dir.txt 2>/dev/null || echo "/sdcard/com.ds.avare")

# 1. Capture final state
screencap -p /sdcard/task_final_state.png

# 2. Check if app is running
APP_RUNNING="false"
if pidof $PACKAGE > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Find new files created after task start
# We look specifically for files created/modified after TASK_START
# Android shell 'find' usually supports -mtime or -newer, but 'stat' is safer if available.
# We will list all files with detailed stats and let python parse, to be robust against shell limitations.

echo "Listing final files..."
# Recursive list with size and modification time (if ls -l works recursively)
# Typically 'ls -lR' provides enough info for basic parsing
ls -lR "$DATA_DIR" > /sdcard/final_file_list_full.txt 2>/dev/null

# Also try to specifically find terrain files and get their stats
# We look for files containing 'terrain', 'elev', or ending in '.t'
POSSIBLE_TERRAIN_FILES=$(find "$DATA_DIR" -type f \( -name "*terrain*" -o -name "*elev*" -o -name "*.t" \) 2>/dev/null)

# Create a JSON-like structure for the files found
# We'll write this to a temp file
TEMP_JSON="/sdcard/found_files.json"
echo "[" > "$TEMP_JSON"
FIRST=1

for f in $POSSIBLE_TERRAIN_FILES; do
    if [ -f "$f" ]; then
        if [ "$FIRST" -eq 0 ]; then echo "," >> "$TEMP_JSON"; fi
        
        # Get size
        SIZE=$(stat -c %s "$f" 2>/dev/null || ls -l "$f" | awk '{print $4}' 2>/dev/null || echo "0")
        # Get mtime (seconds since epoch)
        MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        
        echo "{\"path\": \"$f\", \"size\": $SIZE, \"mtime\": $MTIME}" >> "$TEMP_JSON"
        FIRST=0
    fi
done
echo "]" >> "$TEMP_JSON"

# 4. Create final result JSON
RESULT_JSON="/sdcard/task_result.json"
cat > "$RESULT_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "app_running": $APP_RUNNING,
    "data_dir": "$DATA_DIR",
    "found_files_json_path": "$TEMP_JSON",
    "final_screenshot_path": "/sdcard/task_final_state.png"
}
EOF

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="