#!/bin/bash
# Export script for Search Term Redirect task

echo "=== Exporting Search Term Redirect Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get counts
CURRENT_COUNT=$(magento_query "SELECT COUNT(*) FROM catalogsearch_query" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_term_count 2>/dev/null || echo "0")

echo "Term count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Helper function to get term details
get_term_details() {
    local query_text="$1"
    # Select query_text, redirect, store_id
    # Using LOWER(query_text) to be case-insensitive on lookups
    magento_query "SELECT query_text, redirect, store_id FROM catalogsearch_query WHERE LOWER(TRIM(query_text)) = LOWER(TRIM('$query_text')) ORDER BY query_id DESC LIMIT 1" 2>/dev/null | tail -1
}

# Check for the 3 expected terms
# 1. cheap laptops
TERM1_DATA=$(get_term_details "cheap laptops")
TERM1_EXISTS="false"
TERM1_REDIRECT=""
TERM1_STORE=""
if [ -n "$TERM1_DATA" ]; then
    TERM1_EXISTS="true"
    TERM1_REDIRECT=$(echo "$TERM1_DATA" | awk -F'\t' '{print $2}')
    TERM1_STORE=$(echo "$TERM1_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
fi

# 2. gym equipment
TERM2_DATA=$(get_term_details "gym equipment")
TERM2_EXISTS="false"
TERM2_REDIRECT=""
TERM2_STORE=""
if [ -n "$TERM2_DATA" ]; then
    TERM2_EXISTS="true"
    TERM2_REDIRECT=$(echo "$TERM2_DATA" | awk -F'\t' '{print $2}')
    TERM2_STORE=$(echo "$TERM2_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
fi

# 3. mens outfit
TERM3_DATA=$(get_term_details "mens outfit")
TERM3_EXISTS="false"
TERM3_REDIRECT=""
TERM3_STORE=""
if [ -n "$TERM3_DATA" ]; then
    TERM3_EXISTS="true"
    TERM3_REDIRECT=$(echo "$TERM3_DATA" | awk -F'\t' '{print $2}')
    TERM3_STORE=$(echo "$TERM3_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
fi

# Escape for JSON
TERM1_REDIRECT_ESC=$(echo "$TERM1_REDIRECT" | sed 's/"/\\"/g')
TERM2_REDIRECT_ESC=$(echo "$TERM2_REDIRECT" | sed 's/"/\\"/g')
TERM3_REDIRECT_ESC=$(echo "$TERM3_REDIRECT" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/search_term_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "term1": {
        "exists": $TERM1_EXISTS,
        "redirect": "$TERM1_REDIRECT_ESC",
        "store_id": "${TERM1_STORE:-}"
    },
    "term2": {
        "exists": $TERM2_EXISTS,
        "redirect": "$TERM2_REDIRECT_ESC",
        "store_id": "${TERM2_STORE:-}"
    },
    "term3": {
        "exists": $TERM3_EXISTS,
        "redirect": "$TERM3_REDIRECT_ESC",
        "store_id": "${TERM3_STORE:-}"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/search_term_result.json

echo ""
cat /tmp/search_term_result.json
echo ""
echo "=== Export Complete ==="