#!/system/bin/sh
# Setup script for rank_antifungal_safety_with_axitinib task.

echo "=== Setting up rank_antifungal_safety_with_axitinib task ==="

PACKAGE="com.liverpooluni.ichartoncology"

# Record task start time
date +%s > /sdcard/task_start_time.txt

# Remove any previous result file
rm -f /sdcard/antifungal_ranking.txt

# Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# Press Home to ensure we start from a neutral state
input keyevent KEYCODE_HOME
sleep 1

# Launch the app using robust helper
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart

# Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="