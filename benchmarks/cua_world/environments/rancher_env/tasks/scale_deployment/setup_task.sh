#!/bin/bash
echo "=== Setting up scale_deployment task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Ensure nginx-web is at 2 replicas (reset if previously scaled)
echo "Ensuring nginx-web is at 2 replicas..."
docker exec rancher kubectl scale deployment/nginx-web -n staging --replicas=2 2>/dev/null || true
sleep 5

# Wait for rollout to stabilize
docker exec rancher kubectl rollout status deployment/nginx-web -n staging --timeout=60s 2>/dev/null || true

# Record initial state
INITIAL_REPLICAS=$(docker exec rancher kubectl get deployment nginx-web -n staging -o jsonpath='{.spec.replicas}' 2>/dev/null)
printf '%s' "$INITIAL_REPLICAS" > /tmp/initial_replica_count
echo "Initial replica count: $INITIAL_REPLICAS"

# Navigate Firefox to the nginx-web deployment detail page
echo "Navigating Firefox to nginx-web deployment detail..."
if pgrep -f firefox > /dev/null; then
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool type --clearmodifiers "https://localhost/dashboard/c/local/explorer/apps.deployment/staging/nginx-web" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8
else
    echo "Firefox not running, starting fresh..."
    rm -f /home/ga/.mozilla/firefox/*/lock /home/ga/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/lock 2>/dev/null || true
    rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    su - ga -c "DISPLAY=:1 setsid firefox 'https://localhost/dashboard/c/local/explorer/apps.deployment/staging/nginx-web' > /tmp/firefox_task.log 2>&1 &"
    sleep 12
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|rancher\|nginx" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== scale_deployment task setup complete ==="
echo ""
echo "Task: Scale nginx-web from 2 to 4 replicas"
echo ""
