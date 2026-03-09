#!/bin/bash
# Export script for Homepage Widget task

echo "=== Exporting Homepage Widget Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

INITIAL_COUNT=$(cat /tmp/initial_widget_count.txt 2>/dev/null || echo "0")
ELEC_CAT_ID=$(cat /tmp/electronics_category_id.txt 2>/dev/null || echo "")
CURRENT_COUNT=$(magento_query "SELECT COUNT(*) FROM widget_instance" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "Widget count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Find the widget by title (case-insensitive)
# We select multiple fields to verify configuration
WIDGET_DATA=$(magento_query "SELECT instance_id, instance_type, package_theme, title, widget_parameters 
    FROM widget_instance 
    WHERE LOWER(TRIM(title))='homepage featured electronics' 
    ORDER BY instance_id DESC LIMIT 1" 2>/dev/null | tail -1)

WIDGET_ID=$(echo "$WIDGET_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
WIDGET_TYPE=$(echo "$WIDGET_DATA" | awk -F'\t' '{print $2}')
WIDGET_THEME_ID=$(echo "$WIDGET_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
WIDGET_TITLE=$(echo "$WIDGET_DATA" | awk -F'\t' '{print $4}')
# Parameters might contain tabs or complex chars, so we extract carefully or re-query just that column if needed
# For now, awk handles tab-separated well enough for simple checks

WIDGET_FOUND="false"
[ -n "$WIDGET_ID" ] && WIDGET_FOUND="true"

echo "Widget Found: $WIDGET_FOUND (ID: $WIDGET_ID)"

# Get Theme Name from theme ID
THEME_NAME=""
if [ -n "$WIDGET_THEME_ID" ]; then
    THEME_NAME=$(magento_query "SELECT theme_title FROM theme WHERE theme_id=$WIDGET_THEME_ID" 2>/dev/null | tail -1)
fi
echo "Theme: $THEME_NAME"

# Check Layout Updates (Page and Container)
LAYOUT_HANDLE=""
BLOCK_REFERENCE=""
PAGE_TEMPLATE=""
if [ -n "$WIDGET_ID" ]; then
    LAYOUT_DATA=$(magento_query "SELECT layout_handle, block_reference, page_template 
        FROM widget_instance_page 
        WHERE instance_id=$WIDGET_ID LIMIT 1" 2>/dev/null | tail -1)
    
    LAYOUT_HANDLE=$(echo "$LAYOUT_DATA" | awk -F'\t' '{print $1}')
    BLOCK_REFERENCE=$(echo "$LAYOUT_DATA" | awk -F'\t' '{print $2}')
    PAGE_TEMPLATE=$(echo "$LAYOUT_DATA" | awk -F'\t' '{print $3}')
fi
echo "Layout: handle=$LAYOUT_HANDLE container=$BLOCK_REFERENCE"

# Check Parameters (Product Count and Category Condition)
# We fetch raw parameters separately to avoid awk parsing issues with serialized strings
WIDGET_PARAMS=""
if [ -n "$WIDGET_ID" ]; then
    WIDGET_PARAMS=$(magento_query "SELECT widget_parameters FROM widget_instance WHERE instance_id=$WIDGET_ID" 2>/dev/null | tail -1)
fi

# Check for product count = 5
PARAM_COUNT_5="false"
if echo "$WIDGET_PARAMS" | grep -q "\"products_count\";s:1:\"5\""; then
    PARAM_COUNT_5="true"
elif echo "$WIDGET_PARAMS" | grep -q "products_count.*5"; then
    # Loosest check for resilience
    PARAM_COUNT_5="true"
fi

# Check for category condition (look for category ID)
PARAM_CAT_MATCH="false"
if [ -n "$ELEC_CAT_ID" ]; then
    # Serialized string usually looks like: ... "value";s:X:"CAT_ID" ... inside conditions
    if echo "$WIDGET_PARAMS" | grep -q "$ELEC_CAT_ID"; then
        PARAM_CAT_MATCH="true"
    fi
fi

echo "Params: count_5=$PARAM_COUNT_5 cat_match=$PARAM_CAT_MATCH"

# Escape for JSON
WIDGET_TITLE_ESC=$(echo "$WIDGET_TITLE" | sed 's/"/\\"/g')
THEME_NAME_ESC=$(echo "$THEME_NAME" | sed 's/"/\\"/g')
WIDGET_TYPE_ESC=$(echo "$WIDGET_TYPE" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/homepage_widget_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "widget_found": $WIDGET_FOUND,
    "widget_id": "${WIDGET_ID:-}",
    "widget_title": "$WIDGET_TITLE_ESC",
    "widget_type": "$WIDGET_TYPE_ESC",
    "theme_name": "$THEME_NAME_ESC",
    "layout_handle": "${LAYOUT_HANDLE:-}",
    "block_reference": "${BLOCK_REFERENCE:-}",
    "target_category_id": "${ELEC_CAT_ID:-}",
    "param_count_5": $PARAM_COUNT_5,
    "param_cat_match": $PARAM_CAT_MATCH,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/homepage_widget_result.json

echo ""
cat /tmp/homepage_widget_result.json
echo ""
echo "=== Export Complete ==="