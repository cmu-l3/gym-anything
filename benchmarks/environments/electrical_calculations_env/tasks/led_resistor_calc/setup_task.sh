#!/system/bin/sh
set -e
echo "=== Setting up LED Resistor Calculator task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/tasks/task_start_time.txt

# Create output directory if it doesn't exist
mkdir -p /sdcard/tasks/led_resistor_calc

# Clean up any previous run artifacts
rm -f /sdcard/tasks/led_resistor_result.png
rm -f /sdcard/tasks/led_resistor_ui_dump.xml
rm -f /sdcard/tasks/led_resistor_result.json

PACKAGE="com.hsn.electricalcalculations"

# Ensure app is installed
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: Electrical Calculations app not installed"
    exit 1
fi

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 1

# Launch app to main menu
echo "Launching app..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Dismiss potential initial dialogs/ads by pressing Back then Home then App again
# (A common pattern to clear 'Rate Us' or full screen ads on startup)
input keyevent KEYCODE_BACK
sleep 1
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 3

# Take initial state screenshot for evidence
screencap -p /sdcard/tasks/led_resistor_initial.png

echo "=== Setup complete ==="