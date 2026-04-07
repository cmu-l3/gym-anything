#!/bin/bash
# Export script for execute_db_search_replace_migration

echo "=== Exporting Database Search and Replace Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Core URLs
CURRENT_SITEURL=$(wp_db_query "SELECT option_value FROM wp_options WHERE option_name='siteurl'")
CURRENT_HOME=$(wp_db_query "SELECT option_value FROM wp_options WHERE option_name='home'")

# 2. Check Posts and Meta for remaining staging URLs
POSTS_STAGING_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_content LIKE '%http://staging.local%'")
META_STAGING_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_postmeta WHERE meta_value LIKE '%http://staging.local%'")

# 3. Check Serialized Canary
# If WP-CLI can successfully 'get' it as JSON, the serialization is intact.
# If they used raw SQL, WP-CLI will fail to parse the corrupted array and return empty.
CANARY_JSON=$(wp_cli option get migration_canary_widget --format=json 2>/dev/null || echo "BROKEN")

# Fallback: get raw string in case we need to debug
CANARY_RAW=$(wp_db_query "SELECT option_value FROM wp_options WHERE option_name='migration_canary_widget'")

# 4. Check Site HTTP Status
HTTP_STATUS=$(curl -s -L -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")

echo "Exporting results:"
echo "  SiteURL: $CURRENT_SITEURL"
echo "  Home: $CURRENT_HOME"
echo "  Posts with Staging URL: $POSTS_STAGING_COUNT"
echo "  Meta with Staging URL: $META_STAGING_COUNT"
echo "  Canary JSON: $CANARY_JSON"
echo "  HTTP Status: $HTTP_STATUS"

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "siteurl": "$(json_escape "$CURRENT_SITEURL")",
    "home": "$(json_escape "$CURRENT_HOME")",
    "posts_staging_count": ${POSTS_STAGING_COUNT:-0},
    "meta_staging_count": ${META_STAGING_COUNT:-0},
    "canary_json": "$(json_escape "$CANARY_JSON")",
    "canary_raw": "$(json_escape "$CANARY_RAW")",
    "http_status": "$HTTP_STATUS",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/db_migration_result.json 2>/dev/null || sudo rm -f /tmp/db_migration_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/db_migration_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/db_migration_result.json
chmod 666 /tmp/db_migration_result.json 2>/dev/null || sudo chmod 666 /tmp/db_migration_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/db_migration_result.json"
echo "=== Export complete ==="