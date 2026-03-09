#!/system/bin/sh
# Setup for disable_unused_app_pausing
# Ensures Flight Crew View is installed and the 'Pause app activity' setting is ENABLED (default)

echo "=== Setting up disable_unused_app_pausing task ==="

PACKAGE="com.robert.fcView"

# 1. Ensure App is installed (using environment setup script logic if needed, but assuming env has it)
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: Package $PACKAGE not found!"
    exit 1
fi

# 2. Reset the auto-revoke state to Default/Allowed (Enabled)
# We want the agent to turn it OFF (Ignored)
# MODE_DEFAULT = 0, MODE_ALLOWED = 1, MODE_IGNORED = 2
echo "Resetting autoRevokePermissionsMode..."

# We can try to use appops to force 'allow' (which means allow revocation)
# This command might vary by Android version, but 'cmd appops' is standard
# Op: AUTO_REVOKE_PERMISSIONS_IF_UNUSED
cmd appops set $PACKAGE AUTO_REVOKE_PERMISSIONS_IF_UNUSED allow 2>/dev/null

# Also ensure the app has run recently so it's in the list
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 2
input keyevent KEYCODE_HOME
sleep 1

# 3. Record Initial State
echo "Recording initial state..."
DUMP_OUT=$(dumpsys package $PACKAGE | grep "autoRevokePermissionsMode")
echo "Initial State: $DUMP_OUT"
echo "$DUMP_OUT" > /sdcard/initial_state.txt

# 4. Record Timestamp
date +%s > /sdcard/task_start_time.txt

# 5. Clear recent tasks to ensure clean navigation start (optional, but good for 'settings' tasks)
am force-stop com.android.settings 2>/dev/null

echo "=== Task setup complete ==="