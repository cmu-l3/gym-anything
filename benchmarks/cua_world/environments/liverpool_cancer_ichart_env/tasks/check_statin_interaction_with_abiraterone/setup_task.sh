#!/system/bin/sh
set -e
echo "=== Setting up check_statin_interaction_with_abiraterone task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /sdcard/interaction_result.txt
rm -f /sdcard/task_result.json

# 3. Ensure clean application state
echo "Force stopping app..."
am force-stop com.liverpooluni.ichartoncology
sleep 2

# 4. Launch the application
echo "Launching Cancer iChart..."
monkey -p com.liverpooluni.ichartoncology -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 5. Handle potential "Get Interaction Data" dialog if it appears (though env setup should handle this)
# We assume env setup handled the initial download, but just in case, we wait a bit.
sleep 3

# 6. Capture initial state evidence
screencap -p /sdcard/task_initial_state.png

echo "=== Task setup complete ==="