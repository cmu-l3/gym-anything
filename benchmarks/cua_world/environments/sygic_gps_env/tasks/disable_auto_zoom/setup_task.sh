#!/system/bin/sh
echo "=== Setting up disable_auto_zoom task ==="

PACKAGE="com.sygic.aura"

# Record start time
date +%s > /sdcard/task_start_time.txt

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Ensure Auto-zoom is ON initially (to make the task valid)
# We try to modify the shared preferences if possible via root
# If root isn't available to modify, we assume default is ON or rely on agent workflow
if which su >/dev/null; then
    echo "Root available, enforcing initial state..."
    # Attempt to sed the preference to true
    su -c "sed -i 's/name=\"bAutoZoom\" value=\"false\"/name=\"bAutoZoom\" value=\"true\"/g' /data/data/$PACKAGE/shared_prefs/${PACKAGE}_preferences.xml" 2>/dev/null
    # Ensure permissions are correct after edit
    su -c "chmod 660 /data/data/$PACKAGE/shared_prefs/${PACKAGE}_preferences.xml" 2>/dev/null
    su -c "chown system:system /data/data/$PACKAGE/shared_prefs/${PACKAGE}_preferences.xml" 2>/dev/null
fi

# Go to Home screen
input keyevent KEYCODE_HOME
sleep 1

# Launch Sygic
echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Ensure we are not stuck on a splash screen
# (The environment setup script handles EULA, so we assume main map)

echo "=== Setup complete ==="