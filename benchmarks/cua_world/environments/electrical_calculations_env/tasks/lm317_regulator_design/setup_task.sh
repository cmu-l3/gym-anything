#!/system/bin/sh
echo "=== Setting up LM317 Regulator Design Task ==="

# 1. Prepare Design Specification File
mkdir -p /sdcard/Download
SPECS_FILE="/sdcard/Download/project_specs.txt"

# Clear previous result if exists
rm -f /sdcard/lm317_design.txt

# Create spec file
echo "PROJECT: 12V_TO_9V_FAN_CONTROLLER" > "$SPECS_FILE"
echo "DATE: $(date +%F)" >> "$SPECS_FILE"
echo "COMPONENT: LM317 Adjustable Regulator" >> "$SPECS_FILE"
echo "-----------------------------------" >> "$SPECS_FILE"
echo "INPUT:  12 V" >> "$SPECS_FILE"
echo "TARGET OUTPUT: 9 V" >> "$SPECS_FILE"
echo "REF RESISTOR (R1): 240 Ohms" >> "$SPECS_FILE"
echo "-----------------------------------" >> "$SPECS_FILE"
echo "TASK: Calculate R2. Save result to /sdcard/lm317_design.txt" >> "$SPECS_FILE"
echo "FORMAT: R2=xxxx" >> "$SPECS_FILE"

# 2. Record Task Start Time
date +%s > /sdcard/task_start_time.txt

# 3. Ensure App is Clean and Ready
PACKAGE="com.hsn.electricalcalculations"

# Force stop to ensure clean state
am force-stop "$PACKAGE"
sleep 2

# Go to home screen
input keyevent KEYCODE_HOME
sleep 1

# Launch the app
echo "Launching Electrical Calculations..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
sleep 5

# Dismiss any potential dialogs/ads with Back key (careful not to exit app)
# usually one back press is safe if ad is overlay, but risky if on main menu.
# We'll rely on the agent to handle popups if they persist.

# Ensure we are not on the home screen (basic check)
# If we crashed, relaunch
if ! dumpsys window | grep -q "$PACKAGE"; then
    echo "App failed to launch, retrying..."
    monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
    sleep 5
fi

# 4. Take Initial Screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="