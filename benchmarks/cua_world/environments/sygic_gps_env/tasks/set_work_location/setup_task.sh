#!/system/bin/sh
# Setup script for set_work_location
# Runs on Android device

echo "=== Setting up set_work_location task ==="

PACKAGE="com.sygic.aura"

# 1. Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# 2. Record Task Start Time for Anti-Gaming
date +%s > /sdcard/task_start_time.txt

# 3. Snapshot initial preferences (to detect changes later)
# We use su to access /data/data
echo "Snapshotting initial state..."
su 0 mkdir -p /sdcard/task_snapshot/prefs
su 0 cp -r /data/data/$PACKAGE/shared_prefs/* /sdcard/task_snapshot/prefs/ 2>/dev/null || true
su 0 chmod -R 777 /sdcard/task_snapshot

# 4. Launch Application
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 5. Wait for app to load (simple sleep)
sleep 10

# 6. Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="