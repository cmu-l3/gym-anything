#!/bin/bash
# Export script for Add Website task

echo "=== Exporting Add Website Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png
echo "Final screenshot saved"

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get site counts
INITIAL_COUNT=$(cat /tmp/initial_site_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site" 2>/dev/null || echo "0")

echo "Site count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Expected website details
EXPECTED_SITE_NAME="TechBlog Demo"

# Debug: Show all sites in database
echo ""
echo "=== DEBUG: All sites in database ==="
matomo_query_verbose "SELECT idsite, name, main_url, timezone, currency, ts_created FROM matomo_site ORDER BY idsite DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Query for the expected site (case-insensitive)
echo "Searching for site '$EXPECTED_SITE_NAME'..."
SITE_DATA=$(matomo_query "SELECT idsite, name, main_url, timezone, currency, UNIX_TIMESTAMP(ts_created) as created_ts
     FROM matomo_site
     WHERE LOWER(TRIM(name))=LOWER('$EXPECTED_SITE_NAME')
     ORDER BY idsite DESC LIMIT 1" 2>/dev/null)

# Parse site data
SITE_FOUND="false"
SITE_ID=""
SITE_NAME=""
SITE_URL=""
SITE_TIMEZONE=""
SITE_CURRENCY=""
SITE_CREATED_TS="0"

if [ -n "$SITE_DATA" ]; then
    SITE_FOUND="true"
    SITE_ID=$(echo "$SITE_DATA" | cut -f1)
    SITE_NAME=$(echo "$SITE_DATA" | cut -f2)
    SITE_URL=$(echo "$SITE_DATA" | cut -f3)
    SITE_TIMEZONE=$(echo "$SITE_DATA" | cut -f4)
    SITE_CURRENCY=$(echo "$SITE_DATA" | cut -f5)
    SITE_CREATED_TS=$(echo "$SITE_DATA" | cut -f6)

    echo "Site found:"
    echo "  ID: $SITE_ID"
    echo "  Name: $SITE_NAME"
    echo "  URL: $SITE_URL"
    echo "  Timezone: $SITE_TIMEZONE"
    echo "  Currency: $SITE_CURRENCY"
    echo "  Created timestamp: $SITE_CREATED_TS"
else
    echo "Site '$EXPECTED_SITE_NAME' NOT found in database"

    # Check if any new sites were added
    if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
        echo "Note: New site(s) were added but not with expected name"
        NEWEST=$(matomo_query "SELECT name, main_url FROM matomo_site ORDER BY idsite DESC LIMIT 1" 2>/dev/null)
        echo "Most recent site: $NEWEST"
    fi
fi

# Check if site was created during task window
CREATED_DURING_TASK="false"
if [ "$SITE_CREATED_TS" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
    echo "Site was created during task execution"
else
    echo "Site creation timestamp ($SITE_CREATED_TS) is not after task start ($TASK_START)"
fi

# Get additional URLs for the site (Matomo stores multiple URLs in site_url table)
SITE_URLS=""
if [ -n "$SITE_ID" ]; then
    SITE_URLS=$(matomo_query "SELECT url FROM matomo_site_url WHERE idsite=$SITE_ID" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
fi

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g; s/\r/\\r/g'
}

SITE_NAME_ESC=$(escape_json "$SITE_NAME")
SITE_URL_ESC=$(escape_json "$SITE_URL")
SITE_TIMEZONE_ESC=$(escape_json "$SITE_TIMEZONE")
SITE_CURRENCY_ESC=$(escape_json "$SITE_CURRENCY")
SITE_URLS_ESC=$(escape_json "$SITE_URLS")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/add_website_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_site_count": ${INITIAL_COUNT:-0},
    "current_site_count": ${CURRENT_COUNT:-0},
    "site_found": $SITE_FOUND,
    "created_during_task": $CREATED_DURING_TASK,
    "site": {
        "idsite": "$SITE_ID",
        "name": "$SITE_NAME_ESC",
        "main_url": "$SITE_URL_ESC",
        "additional_urls": "$SITE_URLS_ESC",
        "timezone": "$SITE_TIMEZONE_ESC",
        "currency": "$SITE_CURRENCY_ESC",
        "created_timestamp": $SITE_CREATED_TS
    },
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/add_website_result.json 2>/dev/null || sudo rm -f /tmp/add_website_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_website_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_website_result.json
chmod 666 /tmp/add_website_result.json 2>/dev/null || sudo chmod 666 /tmp/add_website_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/add_website_result.json"
cat /tmp/add_website_result.json

echo ""
echo "=== Export Complete ==="
