#!/bin/bash
echo "=== Setting up create_namespace task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Ensure the 'production' namespace does NOT exist (clean state)
echo "Ensuring clean state - removing production namespace if it exists..."
docker exec rancher kubectl delete namespace production --ignore-not-found=true 2>/dev/null || true
sleep 2

# Record initial namespace list for verification
echo "Recording initial namespace count..."
INITIAL_NS=$(docker exec rancher kubectl get namespaces --no-headers 2>/dev/null | wc -l)
printf '%s' "$INITIAL_NS" > /tmp/initial_namespace_count
echo "Initial namespace count: $INITIAL_NS"

# Navigate the existing Firefox to the Namespaces page
# Firefox was left running and logged in by the post_start hook
echo "Navigating Firefox to Namespaces page..."
if pgrep -f firefox > /dev/null; then
    # Firefox is running - navigate via URL bar
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool type --clearmodifiers "https://localhost/dashboard/c/local/explorer/namespace" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8
else
    # Firefox not running - start it fresh
    echo "Firefox not running, starting fresh..."
    rm -f /home/ga/.mozilla/firefox/*/lock /home/ga/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/lock 2>/dev/null || true
    rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    su - ga -c "DISPLAY=:1 setsid firefox 'https://localhost/dashboard/c/local/explorer/namespace' > /tmp/firefox_task.log 2>&1 &"
    sleep 12
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|rancher\|Namespace" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Wait for page to fully load
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== create_namespace task setup complete ==="
echo ""
echo "Task: Create a namespace called 'production' with label environment=production"
echo "Navigate: Cluster Explorer → Namespaces → Create"
echo ""
