#!/system/bin/sh
echo "=== Setting up set_shortest_route task ==="

PACKAGE="com.sygic.aura"

# 1. Timestamp for anti-gaming
date +%s > /sdcard/task_start_time.txt

# 2. Secure initial state of preferences (requires root to read /data/data)
# We copy them to /sdcard so they are accessible for later comparison
echo "Snapshotting initial preferences..."
su -c "mkdir -p /data/local/tmp/task_snapshots"
su -c "cp -r /data/data/$PACKAGE/shared_prefs /data/local/tmp/task_snapshots/initial_prefs"
# Make readable for export script later
su -c "chmod -R 777 /data/local/tmp/task_snapshots"

# 3. Ensure clean app state (Force stop)
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 2

# 4. Launch App
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 5. Wait for app to load (simple loop)
echo "Waiting for app to load..."
for i in $(seq 1 20); do
    # Check if a Sygic activity is focused
    if dumpsys window | grep -q "mCurrentFocus.*$PACKAGE"; then
        echo "App focused."
        break
    fi
    sleep 1
done
sleep 5

# 6. Capture initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="