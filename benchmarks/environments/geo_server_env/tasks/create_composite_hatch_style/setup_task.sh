#!/bin/bash
echo "=== Setting up create_composite_hatch_style task ==="

source /workspace/scripts/task_utils.sh

# ============================================================
# 1. Clean up potential previous run artifacts
# ============================================================
# Remove the style if it exists to ensure a clean start
echo "Cleaning up any existing 'composite_hatch' style..."
curl -s -u "$GS_AUTH" -X DELETE "${GS_REST}/workspaces/ne/styles/composite_hatch?recurse=true" >/dev/null 2>&1 || true
# Reset ne_countries to a default style (e.g., polygon)
echo "Resetting ne_countries default style..."
curl -s -u "$GS_AUTH" -X PUT "${GS_REST}/layers/ne:ne_countries" \
    -H "Content-Type: application/json" \
    -d '{ "layer": { "defaultStyle": { "name": "polygon" } } }' >/dev/null 2>&1 || true

# ============================================================
# 2. Record Initial State
# ============================================================
date +%s > /tmp/task_start_time.txt
INITIAL_STYLE_COUNT=$(get_style_count)
echo "$INITIAL_STYLE_COUNT" > /tmp/initial_style_count.txt

# ============================================================
# 3. Setup Browser
# ============================================================
# Ensure GeoServer is ready
verify_geoserver_ready 60 || echo "WARNING: GeoServer might not be ready"

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' > /dev/null 2>&1 &"
    sleep 5
fi

# Wait for window and ensure login
wait_for_window "firefox\|mozilla" 30
ensure_logged_in

# Focus Firefox and position mouse centrally
focus_firefox
DISPLAY=:1 xdotool mousemove 960 540 click 1
sleep 1

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="