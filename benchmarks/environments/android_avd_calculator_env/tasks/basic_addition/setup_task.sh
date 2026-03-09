#!/system/bin/sh
# Setup script for basic_addition task (25 + 17 = 42)

echo "=== Setting up basic_addition task ==="

# Make sure we're at home screen first
input keyevent KEYCODE_HOME
sleep 1

# Launch Calculator app
echo "Launching Calculator app..."
monkey -p com.darkempire78.opencalculator -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 2

# Clear any previous calculation
echo "Clearing calculator..."
# Try to tap the AC/C button area (top-left of calculator)
input tap 130 1200 2>/dev/null
sleep 1

echo "=== Task setup completed ==="
echo "Calculator is ready. Agent should now compute 25 + 17 = 42"
