#!/system/bin/sh
# Post-start setup script for Android Calculator environment
# This runs via: adb shell sh /sdcard/scripts/setup_calculator.sh

echo "=== Setting up Android Calculator Environment ==="

# Wait for system to be fully ready
sleep 3

# Press Home to ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 1

# Try to launch Calculator app (try multiple package names)
echo "Launching Calculator..."

# YetCalc (BlissOS default)
am start -n yetzio.yetcalc/.MainActivity 2>/dev/null && echo "Started YetCalc" && exit 0

# BlissOS AOSP Calculator
am start -n com.android.calculator2/.Calculator 2>/dev/null && echo "Started AOSP Calculator" && exit 0

# Google Calculator
am start -n com.google.android.calculator/com.android.calculator2.Calculator 2>/dev/null && echo "Started Google Calculator" && exit 0

# Generic calculator intent
am start -a android.intent.action.MAIN -c android.intent.category.APP_CALCULATOR 2>/dev/null && echo "Started Calculator via intent" && exit 0

echo "Calculator app not found"

echo "=== Calculator setup completed ==="
