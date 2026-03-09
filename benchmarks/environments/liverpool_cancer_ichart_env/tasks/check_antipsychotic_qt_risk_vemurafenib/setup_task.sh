#!/system/bin/sh
echo "=== Setting up Check Antipsychotic Safety Task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/tasks/task_start_time.txt

# Clean up any previous results
rm -f /sdcard/tasks/vemurafenib_quetiapine_check.txt
rm -f /sdcard/tasks/task_result.json

# Ensure the app is installed (should be handled by env setup, but verify)
PACKAGE="com.liverpooluni.ichartoncology"
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: App $PACKAGE not installed!"
    exit 1
fi

# Force stop the app to ensure a clean start state
am force-stop "$PACKAGE"
sleep 1

# Launch the app to the home screen (Welcome screen)
# The agent is expected to navigate from here
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
sleep 5

# Create directory for results if it doesn't exist
mkdir -p /sdcard/tasks

echo "=== Task Setup Complete ==="