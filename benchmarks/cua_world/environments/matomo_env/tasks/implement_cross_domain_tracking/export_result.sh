#!/bin/bash
echo "=== Exporting Cross-Domain Tracking Result ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Read file contents
LANDING_FILE="/home/ga/sites/landing.html"
SHOP_FILE="/home/ga/sites/shop.html"

# Safe read of files (base64 to avoid JSON escaping issues)
if [ -f "$LANDING_FILE" ]; then
    LANDING_CONTENT=$(base64 -w 0 "$LANDING_FILE")
else
    LANDING_CONTENT=""
fi

if [ -f "$SHOP_FILE" ]; then
    SHOP_CONTENT=$(base64 -w 0 "$SHOP_FILE")
else
    SHOP_CONTENT=""
fi

# 2. Check Database for Successful Cross-Domain Visit
# We are looking for a SINGLE visit (idvisit) that has actions on BOTH domains.
# matomo_log_link_visit_action table contains 'url' (though usually it's idaction_url, let's join or check raw)
# Actually, Matomo stores the URL in matomo_log_action (linked via idaction_url).
# However, matomo_log_visit has 'referer_url' and other fields.
# Best check: Find a visit ID where associated actions include both 'localhost' and '127.0.0.1'.

echo "Querying database for cross-domain visits..."

# Helper query to debug
matomo_query_verbose "
SELECT v.idvisit, a.name as action_url
FROM matomo_log_link_visit_action lva
JOIN matomo_log_visit v ON v.idvisit = lva.idvisit
JOIN matomo_log_action a ON a.idaction = lva.idaction_url
WHERE v.visit_last_action_time >= FROM_UNIXTIME($TASK_START)
ORDER BY v.idvisit DESC LIMIT 10
"

# The core check
CROSS_DOMAIN_VISIT_COUNT=$(matomo_query "
SELECT COUNT(DISTINCT lva.idvisit)
FROM matomo_log_link_visit_action lva
JOIN matomo_log_visit v ON v.idvisit = lva.idvisit
JOIN matomo_log_action a ON a.idaction = lva.idaction_url
WHERE v.visit_last_action_time >= FROM_UNIXTIME($TASK_START)
  AND (a.name LIKE '%localhost%' OR a.name LIKE '%127.0.0.1%')
GROUP BY lva.idvisit
HAVING SUM(CASE WHEN a.name LIKE '%localhost%' THEN 1 ELSE 0 END) > 0
   AND SUM(CASE WHEN a.name LIKE '%127.0.0.1%' THEN 1 ELSE 0 END) > 0
")

if [ -z "$CROSS_DOMAIN_VISIT_COUNT" ]; then
    CROSS_DOMAIN_VISIT_COUNT="0"
fi

echo "Found $CROSS_DOMAIN_VISIT_COUNT visits spanning both domains."

# 3. Take final screenshot
take_screenshot /tmp/task_final_state.png

# 4. Generate JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "landing_content_b64": "$LANDING_CONTENT",
    "shop_content_b64": "$SHOP_CONTENT",
    "cross_domain_visits": $CROSS_DOMAIN_VISIT_COUNT,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="