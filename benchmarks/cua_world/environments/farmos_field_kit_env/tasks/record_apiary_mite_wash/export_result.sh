#!/system/bin/sh
# Export script for record_apiary_mite_wash task

echo "=== Exporting results ==="

# 1. Capture final screenshot
screencap -p /sdcard/final_screenshot.png
echo "Screenshot saved."

# 2. Dump UI Hierarchy (backup verification)
uiautomator dump /sdcard/ui_dump.xml
echo "UI dump saved."

# 3. Export Database for programmatic verification
# We need root to access /data/data. We copy it to /sdcard/ which is readable.
# The database file is typically 'farmos-mobile.db' or similar in the databases folder.
# We copy the whole directory content to be safe.

mkdir -p /sdcard/db_export
su 0 cp -r /data/data/org.farmos.app/databases/* /sdcard/db_export/ 2>/dev/null
chmod -R 777 /sdcard/db_export

# List exported files for debugging
ls -l /sdcard/db_export/

# 4. Create a basic result info file
echo "{\"export_time\": \"$(date)\"}" > /sdcard/task_info.json

echo "=== Export complete ==="