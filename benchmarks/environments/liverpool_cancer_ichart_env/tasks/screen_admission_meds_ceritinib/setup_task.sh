#!/system/bin/sh
echo "=== Setting up screen_admission_meds_ceritinib task ==="

# 1. Clean up previous artifacts
rm -f /sdcard/ceritinib_screening_report.txt
rm -f /sdcard/task_result.json

# 2. Record start time for anti-gaming (using generic date +%s if available, else touch)
# Android generic date usually supports +%s
date +%s > /sdcard/task_start_time.txt

# 3. Ensure App is in a clean state (Force stop)
PACKAGE="com.liverpooluni.ichartoncology"
am force-stop $PACKAGE
sleep 2

# 4. Launch App
echo "Launching Liverpool Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1
sleep 5

# 5. Ensure we are not on a sub-screen (Press Back just in case, though force-stop handles this)
# Force-stop clears back stack, so we should be at Home or Splash.

echo "=== Setup Complete ==="