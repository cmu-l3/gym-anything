#!/system/bin/sh
echo "=== Setting up perform_data_backup task ==="

# Create task directory if it doesn't exist (though usually mounted)
mkdir -p /sdcard/scripts/perform_data_backup

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt
echo "Task start time recorded: $(cat /sdcard/task_start_time.txt)"

# Ensure Avare is running and clean
PACKAGE="com.ds.avare"
am force-stop $PACKAGE
sleep 2

# Launch Avare to main map
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Grant permissions just in case
pm grant $PACKAGE android.permission.WRITE_EXTERNAL_STORAGE 2>/dev/null
pm grant $PACKAGE android.permission.READ_EXTERNAL_STORAGE 2>/dev/null

# Clean up ANY existing backup files to ensure we detect a NEW one
# Avare typically stores backups in /sdcard/com.ds.avare/ or /sdcard/Android/data/...
echo "Cleaning old backup files..."
rm -f /sdcard/com.ds.avare/*backup* 2>/dev/null
rm -f /sdcard/com.ds.avare/*.json 2>/dev/null
rm -f /sdcard/Android/data/com.ds.avare/files/*backup* 2>/dev/null

# Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="