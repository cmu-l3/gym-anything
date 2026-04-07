#!/bin/bash
# Setup script for GDPR Erasure Task
# Injects a specific visitor record to be the target of the erasure request

echo "=== Setting up GDPR Erasure Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure basic environment is ready
if ! matomo_is_installed; then
    echo "Waiting for Matomo installation..."
    # triggers setup_matomo.sh logic via check if needed, but usually runs at container start
    sleep 5
fi

# 2. Inject the specific Target Visitor
# Visitor ID: 34c4f238a0b92382
TARGET_ID="34c4f238a0b92382"
TARGET_IP="203.0.113.99"

echo "Injecting target visitor: $TARGET_ID"

# Get a valid site ID
SITE_ID=$(matomo_query "SELECT idsite FROM matomo_site LIMIT 1")
if [ -z "$SITE_ID" ]; then
    # Create default site if none exists
    matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce) VALUES ('Default Site', 'https://example.com', NOW(), 0)"
    SITE_ID=$(matomo_query "SELECT idsite FROM matomo_site LIMIT 1")
fi

# Check if target already exists (idempotency)
EXISTS=$(matomo_query "SELECT COUNT(*) FROM matomo_log_visit WHERE hex(idvisitor) = UPPER('$TARGET_ID')")

if [ "$EXISTS" -eq "0" ]; then
    # Insert multiple visits for this user to make the deletion substantial
    # Visit 1: Yesterday
    VISIT_TIME_1=$(date -d "yesterday 14:00" '+%Y-%m-%d %H:%M:%S')
    
    matomo_query_verbose "INSERT INTO matomo_log_visit (
        idsite, idvisitor, visit_first_action_time, visit_last_action_time,
        visit_total_actions, visit_total_time, visitor_returning, visitor_count_visits,
        location_country, config_browser_name, location_ip, config_os
    ) VALUES (
        $SITE_ID, UNHEX('$TARGET_ID'), '$VISIT_TIME_1', DATE_ADD('$VISIT_TIME_1', INTERVAL 120 SECOND),
        3, 120, 0, 1,
        'de', 'CH', INET6_ATON('$TARGET_IP'), 'W10'
    );"

    # Visit 2: Today
    VISIT_TIME_2=$(date '+%Y-%m-%d 10:00:00')
    matomo_query_verbose "INSERT INTO matomo_log_visit (
        idsite, idvisitor, visit_first_action_time, visit_last_action_time,
        visit_total_actions, visit_total_time, visitor_returning, visitor_count_visits,
        location_country, config_browser_name, location_ip, config_os
    ) VALUES (
        $SITE_ID, UNHEX('$TARGET_ID'), '$VISIT_TIME_2', DATE_ADD('$VISIT_TIME_2', INTERVAL 60 SECOND),
        1, 60, 1, 2,
        'de', 'CH', INET6_ATON('$TARGET_IP'), 'W10'
    );"
    
    echo "Target visitor injected."
else
    echo "Target visitor already exists."
fi

# 3. Ensure "Other" data exists (for collateral damage check)
OTHER_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_log_visit WHERE hex(idvisitor) != UPPER('$TARGET_ID')")
if [ "$OTHER_COUNT" -lt 10 ]; then
    echo "Populating background visitor data..."
    /workspace/scripts/populate_visitor_data.sh > /dev/null 2>&1
fi

# 4. Record Initial State for Verification
TARGET_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_log_visit WHERE hex(idvisitor) = UPPER('$TARGET_ID')")
TOTAL_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_log_visit")
OTHER_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_log_visit WHERE hex(idvisitor) != UPPER('$TARGET_ID')")

# Record task start timestamp
TASK_START=$(date +%s)

# Save initial state to JSON
cat > /tmp/gdpr_initial_state.json << EOF
{
    "target_id": "$TARGET_ID",
    "initial_target_count": $TARGET_COUNT,
    "initial_total_count": $TOTAL_COUNT,
    "initial_other_count": $OTHER_COUNT,
    "task_start_timestamp": $TASK_START
}
EOF

echo "Initial state recorded:"
cat /tmp/gdpr_initial_state.json

# 5. Launch Firefox to Dashboard
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true
su - ga -c "DISPLAY=:1 firefox 'http://localhost/' > /tmp/firefox_task.log 2>&1 &"

wait_for_window "firefox\|mozilla\|Matomo" 60
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="