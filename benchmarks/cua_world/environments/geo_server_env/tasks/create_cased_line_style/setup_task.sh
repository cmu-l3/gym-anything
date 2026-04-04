#!/bin/bash
echo "=== Setting up create_cased_line_style task ==="

source /workspace/scripts/task_utils.sh

# 1. Record initial state (style count)
INITIAL_STYLE_COUNT=$(get_style_count)
echo "$INITIAL_STYLE_COUNT" > /tmp/initial_style_count
echo "Initial style count: $INITIAL_STYLE_COUNT"

# 2. Ensure ne:ne_rivers exists (it should from environment setup, but verify)
LAYER_CHECK=$(gs_rest_status "workspaces/ne/layers/ne_rivers.json")
if [ "$LAYER_CHECK" != "200" ]; then
    echo "WARNING: ne:ne_rivers layer not found. Attempting to fix environment..."
    # Trigger setup script logic again if needed or fail fast
    # For this task, we assume the base env is correct, but let's log it.
    echo "Layer ne_rivers missing check failed: HTTP $LAYER_CHECK"
fi

# 3. Create output directory
mkdir -p /home/ga/output
chown ga:ga /home/ga/output

# 4. Start Firefox and log in
if ! pgrep -f firefox > /dev/null; then
    # Open specifically to the Styles page to save the agent a click
    DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/?wicket:bookmarkablePage=:org.geoserver.wms.web.data.StylePage' &
    sleep 5
fi

wait_for_window "firefox\|mozilla" 45
ensure_logged_in

# 5. Focus window and maximize
focus_firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Generate integrity nonce for result file
generate_result_nonce

# 7. Record start time
date +%s > /tmp/task_start_time.txt

# 8. Snapshot access logs
snapshot_access_log

# 9. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="