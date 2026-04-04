#!/system/bin/sh
echo "=== Setting up check_otc_cough_syrup_safety_abiraterone ==="

# 1. Record start time for anti-gaming (using Unix timestamp)
date +%s > /sdcard/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /sdcard/cough_med_safety.txt
rm -f /sdcard/task_result.json

# 3. Ensure App is running and at a clean state
PACKAGE="com.liverpooluni.ichartoncology"

# Force stop to reset navigation stack
am force-stop $PACKAGE
sleep 2

# Launch the app
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Ensure we are not stuck on a dialog (tap generic safe coordinates if needed, 
# but usually force-stop clears this). 
# Just wait for load.
sleep 3

echo "=== Setup complete ==="