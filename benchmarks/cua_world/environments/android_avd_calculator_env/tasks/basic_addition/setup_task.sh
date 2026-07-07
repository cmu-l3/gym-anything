#!/system/bin/sh
# Setup script for basic_addition task (25 + 17 = 42)

echo "=== Setting up basic_addition task ==="

# Make sure we're at home screen first
input keyevent KEYCODE_HOME
sleep 1

# Launch Calculator app and verify it actually reaches the foreground.
# A silent launch failure would leave the agent on the home screen while
# the task text promises an open calculator. The launcher activity is
# resolved from the package manager rather than hardcoded, and monkey is
# not used because it is broken in this guest image.
echo "Launching Calculator app..."
ACTIVITY=$(cmd package resolve-activity --brief -c android.intent.category.LAUNCHER com.darkempire78.opencalculator | tail -1)
echo "Resolved activity: $ACTIVITY"
LAUNCHED=0
for attempt in 1 2 3 4 5; do
    am start -n "$ACTIVITY" 2>/dev/null
    sleep 2
    if dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp" | grep -q "com.darkempire78.opencalculator"; then
        LAUNCHED=1
        break
    fi
    echo "Calculator not in foreground yet (attempt $attempt), retrying..."
done

if [ "$LAUNCHED" -eq 0 ]; then
    echo "ERROR: Calculator app failed to reach the foreground"
    exit 1
fi

# Clear any previous calculation
echo "Clearing calculator..."
# Try to tap the AC/C button area (top-left of calculator)
input tap 130 1200 2>/dev/null
sleep 1

echo "=== Task setup completed ==="
echo "Calculator is ready. Agent should now compute 25 + 17 = 42"
