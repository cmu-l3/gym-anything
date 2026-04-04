#!/system/bin/sh
# Setup script for inventory_cancer_drug_list task

echo "=== Setting up inventory_cancer_drug_list task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Remove any previous output file to ensure fresh creation
rm -f /sdcard/ichart_drug_inventory.txt
rm -f /sdcard/task_result.json

PACKAGE="com.liverpooluni.ichartoncology"

# Force stop the app to ensure clean state
am force-stop $PACKAGE 2>/dev/null
sleep 2

# Press Home to ensure clean starting point
input keyevent KEYCODE_HOME
sleep 2

# Launch the app fresh
echo "Launching Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Ensure we are not stuck on a splash screen or dialog
# (The environment setup script handles the initial interaction DB download)

# Take screenshot of initial state
screencap -p /sdcard/task_initial_state.png 2>/dev/null || true

echo "=== Setup complete ==="