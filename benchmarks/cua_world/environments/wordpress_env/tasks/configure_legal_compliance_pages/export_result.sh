#!/bin/bash
# Export script for configure_legal_compliance_pages task

echo "=== Exporting configure_legal_compliance_pages result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# ============================================================
# Retrieve Privacy Policy Page Details
# ============================================================
# We search for a published page titled 'Privacy Policy'
PRIVACY_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='page' AND post_status='publish' AND LOWER(TRIM(post_title))='privacy policy' ORDER BY ID DESC LIMIT 1")

PRIVACY_CONTENT=""
if [ -n "$PRIVACY_ID" ]; then
    PRIVACY_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$PRIVACY_ID")
fi

# ============================================================
# Retrieve Terms of Service Page Details
# ============================================================
# We search for a published page titled 'Terms of Service'
TOS_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='page' AND post_status='publish' AND LOWER(TRIM(post_title))='terms of service' ORDER BY ID DESC LIMIT 1")

TOS_CONTENT=""
if [ -n "$TOS_ID" ]; then
    TOS_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$TOS_ID")
fi

# ============================================================
# Retrieve Privacy Setting Option
# ============================================================
PRIVACY_SETTING=$(wp option get wp_page_for_privacy_policy --allow-root 2>/dev/null || echo "0")

echo "Exporting values:"
echo "Privacy Policy ID: ${PRIVACY_ID:-Not found}"
echo "Terms of Service ID: ${TOS_ID:-Not found}"
echo "wp_page_for_privacy_policy: $PRIVACY_SETTING"

# ============================================================
# Create JSON Export (Base64 Encode HTML Content for Safety)
# ============================================================
# Base64 encoding prevents complex HTML/quotes from breaking the JSON payload
PRIVACY_CONTENT_B64=$(echo -n "$PRIVACY_CONTENT" | base64 -w 0)
TOS_CONTENT_B64=$(echo -n "$TOS_CONTENT" | base64 -w 0)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "privacy_page_id": "${PRIVACY_ID:-0}",
    "privacy_content_b64": "$PRIVACY_CONTENT_B64",
    "tos_page_id": "${TOS_ID:-0}",
    "tos_content_b64": "$TOS_CONTENT_B64",
    "privacy_setting": "${PRIVACY_SETTING:-0}",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy to standard output location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="