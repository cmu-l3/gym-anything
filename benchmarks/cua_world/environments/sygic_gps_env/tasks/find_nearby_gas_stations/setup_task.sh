#!/system/bin/sh
set -e
echo "=== Setting up find_nearby_gas_stations task ==="

# 1. Record task start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.sygic.aura"

# 2. Force stop to ensure clean state
am force-stop $PACKAGE 2>/dev/null || true
sleep 2

# 3. Ensure Location is enabled and set (Mountain View, CA)
# Note: In standard Android emulator, we can't easily inject GPS via shell without telnet/grpc
# We rely on the emulator's default location or previous state.
# We try to grant permissions to ensure the app works.
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null || true
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null || true

# 4. Launch Sygic GPS
echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# 5. Handle common startup overlays
# Dismiss "Your map is ready" bottom sheet (Tap X area roughly)
input tap 860 1510 2>/dev/null || true
sleep 2

# Dismiss any full screen promos (Back key)
input keyevent KEYCODE_BACK 2>/dev/null || true
sleep 2

# Ensure we are on the map (Tap center to dismiss any other popups)
input tap 540 1200 2>/dev/null || true
sleep 2

# 6. Capture initial state screenshot
screencap -p /sdcard/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="