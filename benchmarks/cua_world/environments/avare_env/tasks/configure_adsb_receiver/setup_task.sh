#!/system/bin/sh
set -e
echo "=== Setting up configure_adsb_receiver task ==="

# Record task start time for anti-gaming (using date +%s)
date +%s > /sdcard/task_start_time.txt

PREFS_FILE="/data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml"
BACKUP_PATH="/sdcard/initial_prefs_backup.xml"

# Force stop Avare to ensure we start clean
am force-stop com.ds.avare
sleep 2

# Backup initial preferences if they exist (requires root/su)
if su 0 ls "$PREFS_FILE" >/dev/null 2>&1; then
    echo "Backing up initial preferences..."
    su 0 cp "$PREFS_FILE" "$BACKUP_PATH"
    su 0 chmod 666 "$BACKUP_PATH"
else
    echo "No initial preferences found."
    rm -f "$BACKUP_PATH"
fi

# Remove previous output file
rm -f /sdcard/adsb_config.txt

# Launch Avare to main map view
echo "Launching Avare..."
monkey -p com.ds.avare -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Ensure we are not stuck on a dialog (basic heuristic: back key once)
# input keyevent KEYCODE_BACK
# sleep 1

# Take initial screenshot
screencap -p /sdcard/task_initial_state.png

echo "=== Task setup complete ==="