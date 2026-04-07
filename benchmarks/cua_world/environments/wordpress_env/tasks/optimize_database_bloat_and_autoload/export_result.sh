#!/bin/bash
# Export script for optimize_database_bloat_and_autoload task

echo "=== Exporting optimize_database_bloat_and_autoload result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Site Health Check (Anti-Gaming)
SITE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)

# 2. Check Orphaned Metadata
ORPHAN_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_postmeta pm LEFT JOIN wp_posts wp ON pm.post_id = wp.ID WHERE wp.ID IS NULL;" 2>/dev/null | tr -d '\n\r')

# 3. Check Transients
TRANSIENT_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_options WHERE option_name LIKE '%_transient_%';" 2>/dev/null | tr -d '\n\r')

# 4. Check Autoload Trap
AUTOLOAD_EXISTS=$(wp_db_query "SELECT COUNT(*) FROM wp_options WHERE option_name = '_legacy_theme_cache_data';" 2>/dev/null | tr -d '\n\r')
AUTOLOAD_VAL=""
if [ "$AUTOLOAD_EXISTS" -gt 0 ] 2>/dev/null; then
    AUTOLOAD_VAL=$(wp_db_query "SELECT autoload FROM wp_options WHERE option_name = '_legacy_theme_cache_data';" 2>/dev/null | tr -d '\n\r')
fi

# 5. Check Revisions
REVISION_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type = 'revision';" 2>/dev/null | tr -d '\n\r')

# 6. Check Abandoned Table
TABLE_EXISTS=$(wp_db_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'wordpress' AND table_name = 'wp_abandoned_plugin_logs';" 2>/dev/null | tr -d '\n\r')

echo "Current Database State:"
echo "Site HTTP Status: ${SITE_STATUS:-error}"
echo "Orphaned Metadata Count: ${ORPHAN_COUNT:--1}"
echo "Transient Options Count: ${TRANSIENT_COUNT:--1}"
echo "Autoload Option Exists: ${AUTOLOAD_EXISTS:-0}"
echo "Autoload Option Value: ${AUTOLOAD_VAL:-none}"
echo "Revision Count: ${REVISION_COUNT:--1}"
echo "Abandoned Table Exists: ${TABLE_EXISTS:--1}"

# Export to JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "site_http_status": "${SITE_STATUS:-error}",
    "orphan_count": ${ORPHAN_COUNT:--1},
    "transient_count": ${TRANSIENT_COUNT:--1},
    "autoload_exists": ${AUTOLOAD_EXISTS:-0},
    "autoload_val": "${AUTOLOAD_VAL:-none}",
    "revision_count": ${REVISION_COUNT:--1},
    "abandoned_table_exists": ${TABLE_EXISTS:--1},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="