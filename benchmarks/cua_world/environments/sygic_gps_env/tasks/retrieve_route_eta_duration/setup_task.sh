#!/system/bin/sh
echo "=== Setting up retrieve_route_eta_duration task ==="

PACKAGE="com.sygic.aura"
OUTPUT_FILE="/sdcard/trip_duration.txt"

# Record task start time (using date +%s if available, or just writing to file)
date +%s > /sdcard/task_start_time.txt

# Remove previous output file to ensure fresh creation
rm -f "$OUTPUT_FILE"

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Press Home to reset UI stack
input keyevent KEYCODE_HOME
sleep 1

# Launch Sygic GPS Navigation
echo "Launching Sygic..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Handle any potential 'Resume' dialogs or ensure map view
# (Optional: specialized taps could go here if the app gets stuck often)

echo "=== Task setup complete ==="