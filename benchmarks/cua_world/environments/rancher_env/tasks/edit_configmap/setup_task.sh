#!/bin/bash
echo "=== Setting up edit_configmap task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Reset the monitoring-config ConfigMap to original state (scrape_interval: 15s)
echo "Resetting monitoring-config to original state..."
docker exec rancher kubectl apply -f /tmp/app-configmap.yaml 2>/dev/null || true
sleep 3

# Verify current scrape_interval
CURRENT_INTERVAL=$(docker exec rancher kubectl get configmap monitoring-config -n monitoring -o jsonpath='{.data.prometheus\.yml}' 2>/dev/null | grep scrape_interval | head -1 | awk '{print $2}')
echo "Current scrape_interval: $CURRENT_INTERVAL"

# Navigate Firefox to the monitoring-config ConfigMap detail page
echo "Navigating Firefox to monitoring-config ConfigMap..."
if pgrep -f firefox > /dev/null; then
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool type --clearmodifiers "https://localhost/dashboard/c/local/explorer/configmap/monitoring/monitoring-config" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8
else
    echo "Firefox not running, starting fresh..."
    rm -f /home/ga/.mozilla/firefox/*/lock /home/ga/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/lock 2>/dev/null || true
    rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    su - ga -c "DISPLAY=:1 setsid firefox 'https://localhost/dashboard/c/local/explorer/configmap/monitoring/monitoring-config' > /tmp/firefox_task.log 2>&1 &"
    sleep 12
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|rancher\|ConfigMap" 30; then
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

echo "=== edit_configmap task setup complete ==="
echo ""
echo "Task: Edit monitoring-config, change scrape_interval from 15s to 30s"
echo ""
