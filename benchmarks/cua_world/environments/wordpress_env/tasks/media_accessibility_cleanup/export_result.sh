#!/bin/bash
# Export script for media_accessibility_cleanup task

echo "=== Exporting media_accessibility_cleanup result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# ============================================================
# Check Global Media Settings
# ============================================================
UPLOADS_YEARMONTH=$(wp option get uploads_use_yearmonth_folders --allow-root 2>/dev/null || echo "")
THUMBNAIL_W=$(wp option get thumbnail_size_w --allow-root 2>/dev/null || echo "")
THUMBNAIL_H=$(wp option get thumbnail_size_h --allow-root 2>/dev/null || echo "")

# ============================================================
# Check Deleted Attachments
# ============================================================
check_deleted() {
    local title="$1"
    local id=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='$title' AND post_type='attachment' LIMIT 1")
    if [ -z "$id" ] || echo "$id" | grep -qi "error"; then
        echo "true"
    else
        echo "false"
    fi
}

DELETED_PROMO=$(check_deleted "Promo Banner Spring 2024")
DELETED_BLACKFRIDAY=$(check_deleted "Black Friday Sale Old")
DELETED_HOLIDAY=$(check_deleted "Holiday Greetings 2023")

# ============================================================
# Check Alt Text Meta Values
# ============================================================
get_alt_text() {
    local title="$1"
    local id=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='$title' AND post_type='attachment' LIMIT 1")
    
    if [ -n "$id" ] && ! echo "$id" | grep -qi "error"; then
        local alt=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$id AND meta_key='_wp_attachment_image_alt' LIMIT 1")
        if ! echo "$alt" | grep -qi "error"; then
            echo "$alt"
        else
            echo ""
        fi
    else
        echo ""
    fi
}

ALT_CEO=$(get_alt_text "Headshot CEO Sarah")
ALT_DIAGRAM=$(get_alt_text "Accessibility Diagram v2")
ALT_LOBBY=$(get_alt_text "New York Office Lobby")
ALT_CHART=$(get_alt_text "Quarterly Revenue Chart")

# ============================================================
# Format Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "settings": {
        "uploads_use_yearmonth_folders": "$UPLOADS_YEARMONTH",
        "thumbnail_size_w": "$THUMBNAIL_W",
        "thumbnail_size_h": "$THUMBNAIL_H"
    },
    "deleted": {
        "promo_banner": $DELETED_PROMO,
        "black_friday": $DELETED_BLACKFRIDAY,
        "holiday": $DELETED_HOLIDAY
    },
    "alt_texts": {
        "ceo": "$(echo "$ALT_CEO" | sed 's/"/\\"/g' | tr -d '\n')",
        "diagram": "$(echo "$ALT_DIAGRAM" | sed 's/"/\\"/g' | tr -d '\n')",
        "lobby": "$(echo "$ALT_LOBBY" | sed 's/"/\\"/g' | tr -d '\n')",
        "chart": "$(echo "$ALT_CHART" | sed 's/"/\\"/g' | tr -d '\n')"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/media_cleanup_result.json 2>/dev/null || sudo rm -f /tmp/media_cleanup_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/media_cleanup_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/media_cleanup_result.json
chmod 666 /tmp/media_cleanup_result.json 2>/dev/null || sudo chmod 666 /tmp/media_cleanup_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON result exported to /tmp/media_cleanup_result.json"
cat /tmp/media_cleanup_result.json
echo "=== Export complete ==="