#!/system/bin/sh
echo "=== Setting up identify_safer_antiepileptic_with_palbociclib task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Clean up any previous task artifacts
rm -f /sdcard/antiepileptic_safety_report.txt
rm -f /sdcard/task_result.json

PACKAGE="com.liverpooluni.ichartoncology"

# Ensure iChart is installed
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: Cancer iChart is not installed!"
    # In a real scenario, we might try to install it here, but we assume env has it.
    exit 1
fi

# Force stop to ensure clean state (start from fresh launch)
am force-stop $PACKAGE
sleep 1

# Press Home to ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 2

# Take screenshot of initial state
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="