#!/bin/bash
echo "=== Exporting Fix & Verify Tracking Result ==="
source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Get Timestamps & Counts
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_PAGE_VISITS=$(cat /tmp/initial_page_visits.txt 2>/dev/null || echo "0")

# 3. Analyze the HTML File Content
FILE_PATH="/home/ga/Documents/landing_page.html"
FILE_EXISTS="false"
HAS_LOCALHOST="false"
HAS_SITE_ID_1="false"
HAS_TRACK_PAGEVIEW="false"
HAS_HEARTBEAT="false"
HEARTBEAT_VALUE_10="false"

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    CONTENT=$(cat "$FILE_PATH")
    
    # Check for localhost URL (regex for http://localhost/ or //localhost/)
    if echo "$CONTENT" | grep -qE "var u=[\"'](http:)?//localhost/.*[\"']"; then
        HAS_LOCALHOST="true"
    fi

    # Check for Site ID 1
    if echo "$CONTENT" | grep -qE "_paq\.push\(\['setSiteId', ['\"]?1['\"]?\]\)"; then
        HAS_SITE_ID_1="true"
    fi

    # Check for trackPageView (uncommented)
    # Exclude lines starting with //
    if echo "$CONTENT" | grep -vE "^\s*//" | grep -q "_paq.push(\['trackPageView'\])"; then
        HAS_TRACK_PAGEVIEW="true"
    fi

    # Check for Heartbeat
    if echo "$CONTENT" | grep -q "enableHeartBeatTimer"; then
        HAS_HEARTBEAT="true"
        # Check specific value 10
        if echo "$CONTENT" | grep -qE "enableHeartBeatTimer['\"], 10\]"; then
            HEARTBEAT_VALUE_10="true"
        fi
    fi
fi

# 4. Analyze Database for Visits
# Look for a visit to "Summer Sale Landing Page" that happened AFTER task start
# We join log_visit to check the timestamp and log_link_visit_action for the page title
DB_VISIT_FOUND="false"

# Query: Count visits to this page title created after task start
NEW_VISITS=$(matomo_query "
    SELECT COUNT(DISTINCT l.idvisit) 
    FROM matomo_log_link_visit_action l
    JOIN matomo_log_visit v ON l.idvisit = v.idvisit
    WHERE l.name = 'Summer Sale Landing Page'
    AND UNIX_TIMESTAMP(v.visit_first_action_time) >= $TASK_START
" 2>/dev/null || echo "0")

if [ "$NEW_VISITS" -gt 0 ]; then
    DB_VISIT_FOUND="true"
fi

# 5. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "has_localhost": $HAS_LOCALHOST,
    "has_site_id_1": $HAS_SITE_ID_1,
    "has_track_pageview": $HAS_TRACK_PAGEVIEW,
    "has_heartbeat": $HAS_HEARTBEAT,
    "heartbeat_value_10": $HEARTBEAT_VALUE_10,
    "db_visit_found": $DB_VISIT_FOUND,
    "new_visits_count": $NEW_VISITS,
    "task_start": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json