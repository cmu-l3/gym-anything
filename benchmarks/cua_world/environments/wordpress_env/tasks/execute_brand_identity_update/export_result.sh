#!/bin/bash
# Export script for execute_brand_identity_update
echo "=== Exporting brand identity update result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# 1. Check basic options
BLOGNAME=$(wp option get blogname --allow-root 2>/dev/null || echo "")
BLOGDESC=$(wp option get blogdescription --allow-root 2>/dev/null || echo "")
ADMIN_EMAIL=$(wp option get admin_email --allow-root 2>/dev/null || echo "")
NEW_ADMIN_EMAIL=$(wp option get new_admin_email --allow-root 2>/dev/null || echo "")

# 2. Check site logo (Theme Mod)
CUSTOM_LOGO_ID=$(wp eval "echo get_theme_mod('custom_logo');" --allow-root 2>/dev/null || echo "")
LOGO_FILENAME=""
if [ -n "$CUSTOM_LOGO_ID" ] && [ "$CUSTOM_LOGO_ID" != "0" ]; then
    LOGO_FILENAME=$(wp post get "$CUSTOM_LOGO_ID" --field=guid --allow-root 2>/dev/null | awk -F'/' '{print $NF}' || echo "")
fi

# 3. Check site icon (Option)
SITE_ICON_ID=$(wp option get site_icon --allow-root 2>/dev/null || echo "")
ICON_FILENAME=""
if [ -n "$SITE_ICON_ID" ] && [ "$SITE_ICON_ID" != "0" ]; then
    ICON_FILENAME=$(wp post get "$SITE_ICON_ID" --field=guid --allow-root 2>/dev/null | awk -F'/' '{print $NF}' || echo "")
fi

# 4. Check Press Resources Page
PRESS_PAGE_ID=$(wp eval "global \$wpdb; echo \$wpdb->get_var(\"SELECT ID FROM \$wpdb->posts WHERE post_title='Press Resources' AND post_type='page' AND post_status='publish' ORDER BY ID DESC LIMIT 1\");" --allow-root 2>/dev/null || echo "")

PRESS_PAGE_CONTENT=""
PRESS_PAGE_HAS_IMAGE="false"
if [ -n "$PRESS_PAGE_ID" ]; then
    PRESS_PAGE_CONTENT=$(wp post get "$PRESS_PAGE_ID" --field=post_content --allow-root 2>/dev/null || echo "")
    
    # Check if content has an image block or img tag
    if echo "$PRESS_PAGE_CONTENT" | grep -qi "wp:image" || echo "$PRESS_PAGE_CONTENT" | grep -qi "<img"; then
        PRESS_PAGE_HAS_IMAGE="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
PRESS_PAGE_CONTENT_ESC=$(echo "$PRESS_PAGE_CONTENT" | tr '\n' ' ' | sed 's/"/\\"/g' | head -c 5000)
BLOGNAME_ESC=$(echo "$BLOGNAME" | sed 's/"/\\"/g')
BLOGDESC_ESC=$(echo "$BLOGDESC" | sed 's/"/\\"/g')
LOGO_FILENAME_ESC=$(echo "$LOGO_FILENAME" | sed 's/"/\\"/g')
ICON_FILENAME_ESC=$(echo "$ICON_FILENAME" | sed 's/"/\\"/g')

cat > "$TEMP_JSON" << EOF
{
    "blogname": "$BLOGNAME_ESC",
    "blogdescription": "$BLOGDESC_ESC",
    "admin_email": "$ADMIN_EMAIL",
    "new_admin_email": "$NEW_ADMIN_EMAIL",
    "custom_logo_id": "$CUSTOM_LOGO_ID",
    "logo_filename": "$LOGO_FILENAME_ESC",
    "site_icon_id": "$SITE_ICON_ID",
    "icon_filename": "$ICON_FILENAME_ESC",
    "press_page_id": "$PRESS_PAGE_ID",
    "press_page_has_image": $PRESS_PAGE_HAS_IMAGE,
    "press_page_content": "$PRESS_PAGE_CONTENT_ESC",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/brand_identity_result.json 2>/dev/null || sudo rm -f /tmp/brand_identity_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/brand_identity_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/brand_identity_result.json
chmod 666 /tmp/brand_identity_result.json 2>/dev/null || sudo chmod 666 /tmp/brand_identity_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/brand_identity_result.json"
cat /tmp/brand_identity_result.json
echo "=== Export complete ==="