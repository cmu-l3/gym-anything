#!/system/bin/sh
echo "=== Setting up comprehensive_polypharmacy_treatment_selection_review task ==="

PACKAGE="com.liverpooluni.ichartoncology"

# 1. Clean up any previous results BEFORE recording timestamp
rm -f /sdcard/treatment_selection_result.json
rm -f /sdcard/treatment_selection_dump.xml
rm -f /sdcard/treatment_selection_screenshot.png

# 2. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt
echo "Task start time recorded: $(cat /sdcard/task_start_time.txt)"

# 3. Force stop to get clean app state
am force-stop $PACKAGE
sleep 2

# 4. Return to home screen
input keyevent KEYCODE_HOME
sleep 1
input keyevent KEYCODE_HOME
sleep 2

# 5. Launch the app using robust helper
echo "Launching Cancer iChart..."
. /sdcard/scripts/launch_helper.sh
launch_cancer_ichart

echo "=== comprehensive_polypharmacy_treatment_selection_review task setup complete ==="
echo "App is on Welcome screen."
echo "Agent must check Ibrutinib, Venetoclax, and Crizotinib against Ketoconazole, Verapamil, and Warfarin."
echo "Then compare, check alternatives, and navigate to the correct Interaction Details page."
