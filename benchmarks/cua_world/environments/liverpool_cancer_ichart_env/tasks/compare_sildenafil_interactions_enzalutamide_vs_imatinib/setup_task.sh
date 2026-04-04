#!/system/bin/sh
# setup_compare_sildenafil.sh
# Setup for Sildenafil comparison task

echo "=== Setting up Sildenafil Comparison Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
REPORT_PATH="/sdcard/sildenafil_comparison.txt"

# 1. Clean up previous run artifacts
rm -f "$REPORT_PATH"
rm -f /sdcard/task_result.json

# 2. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 3. Ensure clean app state
echo "Force stopping app..."
am force-stop $PACKAGE
sleep 1

# 4. Launch the app to the home screen
echo "Launching Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 5. Ensure we are not stuck in a previous sub-menu (press back if needed, but force-stop usually handles this)
# Just in case, try to maximize/focus if this were desktop, but for Android monkey launch is usually sufficient.

echo "=== Setup Complete ==="