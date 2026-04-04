#!/system/bin/sh
echo "=== Exporting record_yield_comparison_harvest results ==="

PACKAGE="org.farmos.app"
DB_PATH="/data/data/$PACKAGE/databases"
DEST_PATH="/sdcard/task_export"

# Create destination directory
mkdir -p "$DEST_PATH"

# 1. Capture Final Screenshot
echo "Capturing final screenshot..."
screencap -p "$DEST_PATH/final_screenshot.png"

# 2. Export Database
# We use 'run-as' or 'su' to access the private app data
echo "Attempting to export database..."

# Try to find the specific database file
# Usually it's farmos.db, farmos-mobile.db, or similar. We'll copy all .db files.
if [ -d "$DB_PATH" ]; then
    # Try using root/su to copy
    su -c "cp $DB_PATH/*.db $DEST_PATH/" 2>/dev/null
    su -c "chmod 666 $DEST_PATH/*.db" 2>/dev/null
    
    # If su failed or files not found, try run-as (if app is debuggable, though likely release build)
    if [ ! -f "$DEST_PATH/farmos.db" ] && [ ! -f "$DEST_PATH/field-kit.db" ]; then
        echo "Root copy failed or no DB found. Trying generic wildcard copy..."
        su -c "cp /data/data/$PACKAGE/databases/* $DEST_PATH/" 2>/dev/null
        su -c "chmod 666 $DEST_PATH/*" 2>/dev/null
    fi
else
    echo "Database directory not found at $DB_PATH"
fi

# List exported files for debugging
ls -l "$DEST_PATH"

# 3. Create Result JSON Metadata
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "{\"task_start\": $TASK_START, \"task_end\": $TASK_END, \"export_path\": \"$DEST_PATH\"}" > "$DEST_PATH/task_meta.json"

echo "=== Export complete ==="