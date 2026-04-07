#!/system/bin/sh
echo "=== Setting up Venetoclax Polypharmacy Audit Task ==="

# 1. Record task start time for anti-gaming (file modification checks)
date +%s > /sdcard/task_start_time.txt

# 2. Ensure Environment is clean
# Force stop the app so the agent starts from a fresh state (Home screen or App Launcher)
am force-stop com.liverpooluni.ichartoncology
sleep 1

# 3. Clean up previous artifacts
rm -f /sdcard/venetoclax_audit.csv

# 4. Go to Home Screen
input keyevent KEYCODE_HOME
sleep 2

# 5. Launch the app using robust helper
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart

# 6. Capture initial state screenshot (proof of starting condition)
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="