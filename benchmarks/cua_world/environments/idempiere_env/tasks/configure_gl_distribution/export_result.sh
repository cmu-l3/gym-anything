#!/bin/bash
echo "=== Exporting configure_gl_distribution result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "--- collecting database state ---"

# 1. Check Campaigns
# We extract JSON directly from Postgres to handle multiple rows cleanly
CAMPAIGNS_JSON=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -c "
SELECT json_agg(t) FROM (
    SELECT c_campaign_id, value, name, created
    FROM c_campaign 
    WHERE value IN ('SPRING2025', 'SUMMER2025') 
      AND ad_client_id=$CLIENT_ID
) t;
" 2>/dev/null || echo "[]")

# Handle empty result (NULL from json_agg if no rows)
if [ -z "$CAMPAIGNS_JSON" ] || [ "$CAMPAIGNS_JSON" == "" ]; then
    CAMPAIGNS_JSON="[]"
fi

# 2. Check GL Distribution Header
DIST_HEADER_JSON=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -c "
SELECT row_to_json(t) FROM (
    SELECT gl_distribution_id, name, description, created
    FROM gl_distribution 
    WHERE name='Marketing Split 2025' 
      AND ad_client_id=$CLIENT_ID
) t;
" 2>/dev/null || echo "null")

if [ -z "$DIST_HEADER_JSON" ] || [ "$DIST_HEADER_JSON" == "" ]; then
    DIST_HEADER_JSON="null"
fi

# 3. Check Distribution Lines (Joined with Header and Campaign)
DIST_LINES_JSON=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -c "
SELECT json_agg(t) FROM (
    SELECT l.line, l.percent, c.name as campaign_name, c.value as campaign_value, l.created
    FROM gl_distributionline l
    JOIN gl_distribution h ON l.gl_distribution_id = h.gl_distribution_id
    JOIN c_campaign c ON l.c_campaign_id = c.c_campaign_id
    WHERE h.name = 'Marketing Split 2025' 
      AND h.ad_client_id=$CLIENT_ID
    ORDER BY l.percent DESC
) t;
" 2>/dev/null || echo "[]")

if [ -z "$DIST_LINES_JSON" ] || [ "$DIST_LINES_JSON" == "" ]; then
    DIST_LINES_JSON="[]"
fi

# 4. Check if app is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 5. Construct Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "campaigns": $CAMPAIGNS_JSON,
    "distribution_header": $DIST_HEADER_JSON,
    "distribution_lines": $DIST_LINES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="