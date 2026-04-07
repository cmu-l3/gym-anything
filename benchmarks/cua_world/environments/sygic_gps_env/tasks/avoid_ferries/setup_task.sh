#!/system/bin/sh
# Setup script for avoid_ferries task
# Runs on Android device/emulator

echo "=== Setting up avoid_ferries task ==="

PACKAGE="com.sygic.aura"

# 1. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Ensure clean state by force-stopping the app
# (We do not clear data to avoid the First Run Wizard)
am force-stop $PACKAGE
sleep 2

# 3. Go to Home screen
input keyevent KEYCODE_HOME
sleep 1

# 4. Launch Sygic GPS Navigation
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# 5. Wait for app to load (Sygic can be heavy)
sleep 10

# 6. Ensure we are not stuck on a splash screen or dialog
# Tap roughly in the center just in case a "What's new" sheet is up
# input tap 540 1500 
# (Commented out to avoid accidental map clicks, agent should handle dialogs)

# 7. Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="