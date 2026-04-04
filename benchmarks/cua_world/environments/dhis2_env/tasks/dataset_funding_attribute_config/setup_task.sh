#!/bin/bash
# Setup script for Dataset Funding Attribute Config task

echo "=== Setting up Dataset Funding Attribute Config Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallback for DHIS2 API check
if ! type check_dhis2_health &>/dev/null; then
    check_dhis2_health() {
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
        if [ "$http_code" = "200" ] || [ "$http_code" = "401" ]; then
            return 0
        fi
        return 1
    }
fi

# 1. Verify DHIS2 is ready
echo "Checking DHIS2 health..."
for i in {1..30}; do
    if check_dhis2_health; then
        echo "DHIS2 is ready."
        break
    fi
    echo "Waiting for DHIS2..."
    sleep 2
done

# 2. Record Task Start Time (for anti-gaming)
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
echo "Task start time: $(cat /tmp/task_start_iso)"

# 3. Clean up any previous attempts (Optional but good for idempotency)
# We won't aggressively delete to avoid breaking the DB, but we'll log if they exist.
echo "Checking for existing metadata..."
EXISTING_COMBO=$(dhis2_api "categoryCombos?filter=name:eq:Funding Source 2025" 2>/dev/null)
echo "Pre-existing check: $EXISTING_COMBO"

# 4. Prepare Browser
echo "Launching Firefox..."
DHIS2_URL="http://localhost:8080"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
else
    # Reload/Home
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &"
fi

# Wait for window and maximize
wait_for_window "firefox\|mozilla\|DHIS" 30
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Take Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="