#!/bin/bash
# Export script for XML Sitemap Setup task

echo "=== Exporting XML Sitemap Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check Configuration Settings in core_config_data
# We look for specific paths:
# sitemap/category/changefreq, sitemap/category/priority
# sitemap/product/changefreq, sitemap/product/priority
# sitemap/page/changefreq, sitemap/page/priority

echo "Querying configuration settings..."

CAT_FREQ=$(magento_query "SELECT value FROM core_config_data WHERE path='sitemap/category/changefreq'" 2>/dev/null | tail -1)
CAT_PRIO=$(magento_query "SELECT value FROM core_config_data WHERE path='sitemap/category/priority'" 2>/dev/null | tail -1)

PROD_FREQ=$(magento_query "SELECT value FROM core_config_data WHERE path='sitemap/product/changefreq'" 2>/dev/null | tail -1)
PROD_PRIO=$(magento_query "SELECT value FROM core_config_data WHERE path='sitemap/product/priority'" 2>/dev/null | tail -1)

PAGE_FREQ=$(magento_query "SELECT value FROM core_config_data WHERE path='sitemap/page/changefreq'" 2>/dev/null | tail -1)
PAGE_PRIO=$(magento_query "SELECT value FROM core_config_data WHERE path='sitemap/page/priority'" 2>/dev/null | tail -1)

echo "Config Found:"
echo "  Cat: $CAT_FREQ / $CAT_PRIO"
echo "  Prod: $PROD_FREQ / $PROD_PRIO"
echo "  Page: $PAGE_FREQ / $PAGE_PRIO"

# 2. Check Sitemap Database Record
echo "Querying sitemap table..."
SITEMAP_RECORD=$(magento_query "SELECT sitemap_id, sitemap_filename, sitemap_path, sitemap_time FROM sitemap WHERE sitemap_filename='sitemap.xml' ORDER BY sitemap_id DESC LIMIT 1" 2>/dev/null | tail -1)

SITEMAP_FOUND="false"
SITEMAP_ID=""
SITEMAP_FILENAME=""
SITEMAP_PATH=""
SITEMAP_TIME=""

if [ -n "$SITEMAP_RECORD" ]; then
    SITEMAP_FOUND="true"
    SITEMAP_ID=$(echo "$SITEMAP_RECORD" | awk -F'\t' '{print $1}')
    SITEMAP_FILENAME=$(echo "$SITEMAP_RECORD" | awk -F'\t' '{print $2}')
    SITEMAP_PATH=$(echo "$SITEMAP_RECORD" | awk -F'\t' '{print $3}')
    SITEMAP_TIME=$(echo "$SITEMAP_RECORD" | awk -F'\t' '{print $4}')
fi
echo "DB Record: Found=$SITEMAP_FOUND ID=$SITEMAP_ID Path=$SITEMAP_PATH Filename=$SITEMAP_FILENAME Time=$SITEMAP_TIME"

# 3. Check Physical File Existence
SITEMAP_FILE="/var/www/html/magento/pub/sitemap.xml"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CONTENT_VALID="false"

if [ -f "$SITEMAP_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$SITEMAP_FILE" 2>/dev/null || echo "0")
    
    # Check if it looks like an XML sitemap (contains urlset)
    if grep -q "<urlset" "$SITEMAP_FILE" && grep -q "http" "$SITEMAP_FILE"; then
        FILE_CONTENT_VALID="true"
    fi
fi
echo "File Check: Exists=$FILE_EXISTS Size=$FILE_SIZE Valid=$FILE_CONTENT_VALID"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/sitemap_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config": {
        "category_freq": "${CAT_FREQ:-}",
        "category_prio": "${CAT_PRIO:-}",
        "product_freq": "${PROD_FREQ:-}",
        "product_prio": "${PROD_PRIO:-}",
        "page_freq": "${PAGE_FREQ:-}",
        "page_prio": "${PAGE_PRIO:-}"
    },
    "db_record": {
        "found": $SITEMAP_FOUND,
        "filename": "${SITEMAP_FILENAME:-}",
        "path": "${SITEMAP_PATH:-}",
        "time": "${SITEMAP_TIME:-}"
    },
    "file": {
        "exists": $FILE_EXISTS,
        "size_bytes": $FILE_SIZE,
        "content_valid": $FILE_CONTENT_VALID
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/sitemap_result.json

echo ""
cat /tmp/sitemap_result.json
echo ""
echo "=== Export Complete ==="