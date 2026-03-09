#!/system/bin/sh
# Export script for record_subsoiling_tillage task
# Runs on Android device via adb shell

echo "=== Exporting Subsoiling Task Result ==="

PACKAGE="org.farmos.app"
DB_PATH="/data/data/$PACKAGE/databases/farmos_logs.db" # Standard Drupal/farmOS app DB name often varies, checking common ones
# Fallback to wildcard copy
DEST_DIR="/sdcard/task_results"
mkdir -p "$DEST_DIR"

# 1. Capture Final Screenshot
screencap -p "$DEST_DIR/task_final.png"

# 2. Extract Database (Requires Root/Su)
# We try to copy the internal database to sdcard so it can be pulled by the verifier
echo "Attempting to extract database..."
su -c "cp /data/data/$PACKAGE/databases/*.db $DEST_DIR/" 2>/dev/null || echo "Failed to copy DB (might not have root)"
su -c "chmod 666 $DEST_DIR/*.db" 2>/dev/null

# 3. Create Result JSON
# We create a simple JSON with timestamp and file info
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
DB_EXISTS="false"

if ls $DEST_DIR/*.db 1> /dev/null 2>&1; then
    DB_EXISTS="true"
fi

cat > "$DEST_DIR/result.json" <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_extracted": $DB_EXISTS,
    "screenshot_path": "$DEST_DIR/task_final.png"
}
EOF

echo "Export complete. Files in $DEST_DIR"