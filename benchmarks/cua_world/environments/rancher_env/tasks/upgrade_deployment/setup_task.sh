#!/bin/bash
echo "=== Setting up upgrade_deployment task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Ensure nginx-web is running with original image (nginx:1.25-alpine)
echo "Ensuring nginx-web is running nginx:1.25-alpine..."
CURRENT_IMAGE=$(docker exec rancher kubectl get deployment nginx-web -n staging -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
echo "Current image: $CURRENT_IMAGE"

if [ "$CURRENT_IMAGE" != "nginx:1.25-alpine" ]; then
    echo "Resetting nginx-web to nginx:1.25-alpine..."
    docker exec rancher kubectl set image deployment/nginx-web nginx=nginx:1.25-alpine -n staging 2>/dev/null || true
    sleep 5
    docker exec rancher kubectl rollout status deployment/nginx-web -n staging --timeout=120s 2>/dev/null || true
fi

# Pre-pull the target image inside the Rancher container to speed up the upgrade
echo "Pre-pulling nginx:1.26-alpine inside K3s..."
docker exec rancher ctr images pull docker.io/library/nginx:1.26-alpine 2>/dev/null || true

# Record initial state
printf '%s' "$CURRENT_IMAGE" > /tmp/initial_deployment_image
echo "Initial image: $CURRENT_IMAGE"

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

echo "=== upgrade_deployment task setup complete ==="
echo ""
echo "Task: Upgrade nginx-web from nginx:1.25-alpine to nginx:1.26-alpine"
echo ""
