#!/bin/bash
echo "=== Setting up deploy_workload task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Ensure the 'web-frontend' deployment does NOT exist in default namespace (clean state)
echo "Ensuring clean state - removing web-frontend deployment if it exists..."
docker exec rancher kubectl delete deployment web-frontend -n default --ignore-not-found=true 2>/dev/null || true
sleep 2

# Record initial deployment list for verification
echo "Recording initial deployment count in default namespace..."
INITIAL_DEPLOY=$(docker exec rancher kubectl get deployments -n default --no-headers 2>/dev/null | wc -l)
printf '%s' "$INITIAL_DEPLOY" > /tmp/initial_deployment_count
echo "Initial deployment count (default ns): $INITIAL_DEPLOY"

# Navigate the existing Firefox to the Deployments page
# Firefox was left running and logged in by the post_start hook
echo "Navigating Firefox to Deployments page..."
if pgrep -f firefox > /dev/null; then
    # Firefox is running - navigate via URL bar
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool type --clearmodifiers "https://localhost/dashboard/c/local/explorer/apps.deployment" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8
else
    # Firefox not running - start it fresh
    echo "Firefox not running, starting fresh..."
    rm -f /home/ga/.mozilla/firefox/*/lock /home/ga/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/lock 2>/dev/null || true
    rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    su - ga -c "DISPLAY=:1 setsid firefox 'https://localhost/dashboard/c/local/explorer/apps.deployment' > /tmp/firefox_task.log 2>&1 &"
    sleep 12
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|rancher\|Deployment" 30; then
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

echo "=== deploy_workload task setup complete ==="
echo ""
echo "Task: Deploy a workload named 'web-frontend' with nginx:latest, 2 replicas, in default namespace"
echo "Navigate: Cluster Explorer → Workloads → Deployments → Create"
echo ""
