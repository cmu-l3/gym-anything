#!/bin/bash
echo "=== Setting up configure_campaign_trackers task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming validation)
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# Verify the target campaign or trackers do not already exist, to ensure a clean slate
if suitecrm_db_query "SELECT id FROM campaigns WHERE name='Industrial Sensor Launch 2026' AND deleted=0" | grep -q "."; then
    echo "WARNING: Target campaign already exists, cleaning up for task execution..."
    soft_delete_record "campaigns" "name='Industrial Sensor Launch 2026'"
fi

suitecrm_db_query "UPDATE campaign_trkrs SET deleted=1 WHERE tracker_name IN ('LinkedIn Promo', 'Trade Show Kiosk', 'Partner Email')"

# Ensure logged in and navigate to Campaigns list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Campaigns&action=index"
sleep 5

# Ensure the window is fully focused and maximized
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/configure_campaign_trackers_initial.png

echo "=== configure_campaign_trackers task setup complete ==="