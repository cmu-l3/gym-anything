#!/system/bin/sh
echo "=== Exporting import_user_waypoints results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
screencap -p /sdcard/task_final.png

# Dump UI hierarchy to XML (useful for verifier to find text "LZ_ALPHA")
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

# Check if GPX file still exists (sanity check)
if [ -f "/sdcard/company_lz.gpx" ]; then
    GPX_EXISTS="true"
else
    GPX_EXISTS="false"
fi

# Try to check internal database if we have root/su access
# Avare typically stores user waypoints in a SQLite DB
# We will try to dump the database user waypoints table if possible
DB_DUMP_SUCCESS="false"
DB_CONTENT=""

# Attempt to query the database via sqlite3 if available and accessible
# Note: location of DB varies, typically /data/data/com.ds.avare/databases/
# This command might fail if not root, which is handled gracefully
if which sqlite3 >/dev/null; then
    # Try generic location
    DB_PATH="/data/data/com.ds.avare/databases/avare.db" 
    # Or sometimes landmarks are in a separate file. We'll try to grep strings from the DB directory if direct query fails
    
    # Simple grep check if we can access the directory (requires root/su)
    if su -c "ls /data/data/com.ds.avare/databases/" >/dev/null 2>&1; then
       # Check if LZ_ALPHA is in the database files
       if su -c "grep -r 'LZ_ALPHA' /data/data/com.ds.avare/databases/" >/dev/null 2>&1; then
           DB_CONTENT="LZ_ALPHA found in database files"
           DB_DUMP_SUCCESS="true"
       fi
    fi
fi

# Create JSON result
# Note: We use a simple echo structure to avoid python dependency issues in shell
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"gpx_file_exists\": $GPX_EXISTS," >> /sdcard/task_result.json
echo "  \"db_check_success\": $DB_DUMP_SUCCESS," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"," >> /sdcard/task_result.json
echo "  \"ui_dump_path\": \"/sdcard/ui_dump.xml\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result exported to /sdcard/task_result.json"