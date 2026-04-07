#!/bin/bash
# Export script for customize_fse_templates task
# Collects FSE template modifications from the database

echo "=== Exporting customize_fse_templates result ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Initialize variables
T404_FOUND="false"
T404_ID=""
T404_CONTENT=""
T404_MODIFIED=""

FOOTER_FOUND="false"
FOOTER_ID=""
FOOTER_CONTENT=""
FOOTER_MODIFIED=""

# ============================================================
# 1. Check for 404 Template Override
# ============================================================
echo "Querying for 404 template override..."
# In FSE, templates are saved in wp_posts as 'wp_template' post type
T404_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='wp_template' AND post_name LIKE '%404%' AND post_status='publish' ORDER BY ID DESC LIMIT 1")

if [ -n "$T404_ID" ]; then
    T404_FOUND="true"
    T404_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$T404_ID")
    T404_MODIFIED=$(wp_db_query "SELECT UNIX_TIMESTAMP(post_modified) FROM wp_posts WHERE ID=$T404_ID")
    echo "Found 404 template override (ID: $T404_ID)"
else
    echo "No 404 template override found."
fi

# ============================================================
# 2. Check for Footer Template Part Override
# ============================================================
echo "Querying for footer template part override..."
FOOTER_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='wp_template_part' AND post_name LIKE '%footer%' AND post_status='publish' ORDER BY ID DESC LIMIT 1")

if [ -n "$FOOTER_ID" ]; then
    FOOTER_FOUND="true"
    FOOTER_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$FOOTER_ID")
    FOOTER_MODIFIED=$(wp_db_query "SELECT UNIX_TIMESTAMP(post_modified) FROM wp_posts WHERE ID=$FOOTER_ID")
    echo "Found footer template override (ID: $FOOTER_ID)"
else
    echo "No footer template override found."
fi

# ============================================================
# 3. HTTP Front-end Check (Secondary validation)
# ============================================================
HTTP_404_TEXT_FOUND="false"
# Fetch a guaranteed 404 page and check if the custom text appears in the rendered HTML
RANDOM_URL="http://localhost/this-page-definitely-does-not-exist-$(date +%s)"
if curl -s "$RANDOM_URL" | grep -qi "Oops! We couldn't find that page."; then
    HTTP_404_TEXT_FOUND="true"
fi

# ============================================================
# Escape contents for JSON
# ============================================================
T404_CONTENT_ESC=$(echo "$T404_CONTENT" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r' | head -c 10000)
FOOTER_CONTENT_ESC=$(echo "$FOOTER_CONTENT" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r' | head -c 10000)

# ============================================================
# Generate JSON Result
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "template_404": {
        "found": $T404_FOUND,
        "id": "${T404_ID:-}",
        "content": "$T404_CONTENT_ESC",
        "modified_ts": ${T404_MODIFIED:-0}
    },
    "template_footer": {
        "found": $FOOTER_FOUND,
        "id": "${FOOTER_ID:-}",
        "content": "$FOOTER_CONTENT_ESC",
        "modified_ts": ${FOOTER_MODIFIED:-0}
    },
    "http_404_rendered_correctly": $HTTP_404_TEXT_FOUND
}
EOF

# Move to final location safely
rm -f /tmp/customize_fse_templates_result.json 2>/dev/null || sudo rm -f /tmp/customize_fse_templates_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/customize_fse_templates_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/customize_fse_templates_result.json
chmod 666 /tmp/customize_fse_templates_result.json 2>/dev/null || sudo chmod 666 /tmp/customize_fse_templates_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/customize_fse_templates_result.json"
echo "=== Export complete ==="