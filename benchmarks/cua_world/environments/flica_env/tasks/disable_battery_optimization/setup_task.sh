#!/system/bin/sh
set -e
echo "=== Setting up disable_battery_optimization task ==="

PACKAGE="com.robert.fcView"
TASK_DIR="/sdcard/tasks/disable_battery_optimization"

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 1. CLEANUP: Force remove package from whitelist
# The '-' prefix removes the package from the whitelist
echo "Removing $PACKAGE from battery optimization whitelist..."
dumpsys deviceidle whitelist -$PACKAGE 2>/dev/null || true
sleep 1

# Reset appops to default (Optimized/Restricted behavior)
cmd appops set $PACKAGE RUN_ANY_IN_BACKGROUND default 2>/dev/null || true
cmd appops set $PACKAGE RUN_IN_BACKGROUND default 2>/dev/null || true

# Verify cleanup
WHITELIST_CHECK=$(dumpsys deviceidle whitelist | grep "$PACKAGE" || echo "")
if [ -n "$WHITELIST_CHECK" ]; then
    echo "WARNING: Failed to remove package from whitelist. Setup may be compromised."
else
    echo "Confirmed: Package is NOT in whitelist (default state)."
fi

# Record initial state for verifier
echo "$WHITELIST_CHECK" > /sdcard/initial_whitelist_state.txt

# 2. APP SETUP: Ensure app is installed and logged in
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: Flight Crew View is not installed!"
    exit 1
fi

# Use the environment's login helper to ensure we start at the Friends page
echo "Running login helper..."
sh /sdcard/scripts/login_helper.sh

# 3. CAPTURE INITIAL STATE
echo "Capturing initial screenshot..."
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="