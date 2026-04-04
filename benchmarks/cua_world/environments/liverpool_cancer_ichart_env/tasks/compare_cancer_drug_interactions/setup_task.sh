#!/system/bin/sh
# Setup script for compare_cancer_drug_interactions task

echo "=== Setting up compare_cancer_drug_interactions task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.liverpooluni.ichartoncology"

# Force stop to get a clean state
am force-stop $PACKAGE
sleep 2

# Press Home to ensure we start from a clean launcher state
input keyevent KEYCODE_HOME
sleep 1

# Launch the app
echo "Launching Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Ensure we are not on a crash dialog or unexpected screen
# If the "Get Interaction Data" dialog appears (unlikely if env setup worked), 
# we rely on the agent to handle it or the app to be ready.
# We just ensure the app is in the foreground.

CURRENT_FOCUS=$(dumpsys window | grep mCurrentFocus)
echo "Current focus: $CURRENT_FOCUS"

# Take screenshot of initial state
screencap -p /sdcard/task_initial.png 2>/dev/null
echo "Initial screenshot captured"

echo "=== Task setup complete ==="