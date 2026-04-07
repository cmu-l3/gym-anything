#!/bin/bash
# Export script for setup_contact_form task

echo "=== Exporting setup_contact_form result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# 1. Check Plugin Status
CF7_ACTIVE="false"
if wp plugin is-active contact-form-7 --allow-root 2>/dev/null; then
    CF7_ACTIVE="true"
    echo "Contact Form 7 is active"
else
    echo "Contact Form 7 is NOT active"
fi

# 2. Find the Form
FORM_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='wpcf7_contact_form' AND post_title='General Inquiry Form' AND post_status='publish' ORDER BY ID DESC LIMIT 1")

FORM_FOUND="false"
FORM_CONTENT_B64=""
MAIL_META_B64=""

if [ -n "$FORM_ID" ]; then
    FORM_FOUND="true"
    echo "Found 'General Inquiry Form' with ID: $FORM_ID"
    
    # Get raw form template (content)
    FORM_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$FORM_ID")
    # Base64 encode to safely pass through JSON without formatting/escaping issues
    FORM_CONTENT_B64=$(echo -n "$FORM_CONTENT" | base64 -w 0)
    
    # Get mail meta (contains To, Subject, Body etc. in serialized PHP array)
    MAIL_META=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$FORM_ID AND meta_key='_mail'")
    MAIL_META_B64=$(echo -n "$MAIL_META" | base64 -w 0)
else
    echo "'General Inquiry Form' NOT found"
fi

# 3. Find the Page
PAGE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='page' AND post_title='Contact Us' AND post_status='publish' ORDER BY ID DESC LIMIT 1")

PAGE_FOUND="false"
PAGE_CONTENT_B64=""

if [ -n "$PAGE_ID" ]; then
    PAGE_FOUND="true"
    echo "Found published 'Contact Us' page with ID: $PAGE_ID"
    
    # Get page content
    PAGE_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$PAGE_ID")
    PAGE_CONTENT_B64=$(echo -n "$PAGE_CONTENT" | base64 -w 0)
else
    echo "Published 'Contact Us' page NOT found"
fi

# Build JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "cf7_active": $CF7_ACTIVE,
    "form_found": $FORM_FOUND,
    "form_id": "${FORM_ID:-}",
    "form_content_b64": "$FORM_CONTENT_B64",
    "mail_meta_b64": "$MAIL_META_B64",
    "page_found": $PAGE_FOUND,
    "page_id": "${PAGE_ID:-}",
    "page_content_b64": "$PAGE_CONTENT_B64",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save and set permissions safely
rm -f /tmp/setup_contact_form_result.json 2>/dev/null || sudo rm -f /tmp/setup_contact_form_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/setup_contact_form_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/setup_contact_form_result.json
chmod 666 /tmp/setup_contact_form_result.json 2>/dev/null || sudo chmod 666 /tmp/setup_contact_form_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/setup_contact_form_result.json"
echo "=== Export complete ==="