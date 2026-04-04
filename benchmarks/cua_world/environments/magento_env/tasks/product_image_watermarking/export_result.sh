#!/bin/bash
# Export script for Product Image Watermarking task

echo "=== Exporting Product Image Watermarking Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Configuration paths to check
# Scope for "Main Website" is usually 'websites' and scope_id = 1 (assuming single website setup)
# Note: scope_id might vary if the user created new websites, but Main Website is usually 1.

SCOPES_TO_CHECK="websites"
SCOPE_IDS_TO_CHECK="1"

# Helper function to get config value
get_config_value() {
    local path="$1"
    local scope="$2"
    local scope_id="$3"
    
    magento_query "SELECT value FROM core_config_data WHERE path='$path' AND scope='$scope' AND scope_id=$scope_id" 2>/dev/null | tail -1
}

echo "Checking configuration for scope='$SCOPES_TO_CHECK' id=$SCOPE_IDS_TO_CHECK..."

# 1. Base Image Settings
BASE_IMAGE_FILE=$(get_config_value "design/watermark/image_image" "$SCOPES_TO_CHECK" "$SCOPE_IDS_TO_CHECK")
BASE_IMAGE_OPACITY=$(get_config_value "design/watermark/image_imageOpacity" "$SCOPES_TO_CHECK" "$SCOPE_IDS_TO_CHECK")
BASE_IMAGE_POSITION=$(get_config_value "design/watermark/image_position" "$SCOPES_TO_CHECK" "$SCOPE_IDS_TO_CHECK")

# 2. Small Image Settings
SMALL_IMAGE_FILE=$(get_config_value "design/watermark/small_image_image" "$SCOPES_TO_CHECK" "$SCOPE_IDS_TO_CHECK")
SMALL_IMAGE_OPACITY=$(get_config_value "design/watermark/small_image_imageOpacity" "$SCOPES_TO_CHECK" "$SCOPE_IDS_TO_CHECK")
SMALL_IMAGE_POSITION=$(get_config_value "design/watermark/small_image_position" "$SCOPES_TO_CHECK" "$SCOPE_IDS_TO_CHECK")

# 3. Thumbnail Settings
THUMB_IMAGE_FILE=$(get_config_value "design/watermark/thumbnail_image" "$SCOPES_TO_CHECK" "$SCOPE_IDS_TO_CHECK")
THUMB_IMAGE_OPACITY=$(get_config_value "design/watermark/thumbnail_imageOpacity" "$SCOPES_TO_CHECK" "$SCOPE_IDS_TO_CHECK")
THUMB_IMAGE_POSITION=$(get_config_value "design/watermark/thumbnail_image_position" "$SCOPES_TO_CHECK" "$SCOPE_IDS_TO_CHECK")

echo "Base Image: File='$BASE_IMAGE_FILE', Opacity='$BASE_IMAGE_OPACITY', Pos='$BASE_IMAGE_POSITION'"
echo "Small Image: File='$SMALL_IMAGE_FILE', Opacity='$SMALL_IMAGE_OPACITY', Pos='$SMALL_IMAGE_POSITION'"
echo "Thumbnail: File='$THUMB_IMAGE_FILE', Opacity='$THUMB_IMAGE_OPACITY', Pos='$THUMB_IMAGE_POSITION'"

# Verify file existence
# Magento stores uploads in pub/media/ (relative path stored in DB usually starts without slash or with upload dir)
# The DB value for file upload is usually something like "default/watermark.png" or just "watermark.png"
# It resides in /var/www/html/magento/pub/media/xmlconnect/system/video/player/ ... wait, no.
# For design config, it's usually in `pub/media/core/design/watermark/...` or similar.
# Actually, standard Magento upload puts it in `pub/media/` + the relative path.
# Let's check if the file exists on disk if a path is provided.

check_file_exists() {
    local db_path="$1"
    if [ -z "$db_path" ]; then
        echo "false"
        return
    fi
    
    # Try common locations
    if [ -f "/var/www/html/magento/pub/media/$db_path" ]; then
        echo "true"
    elif [ -f "/var/www/html/magento/pub/media/watermark/$db_path" ]; then
        echo "true"
    # Fallback search
    elif find /var/www/html/magento/pub/media -name "$(basename "$db_path")" | grep -q .; then
        echo "true"
    else
        echo "false"
    fi
}

BASE_EXISTS=$(check_file_exists "$BASE_IMAGE_FILE")
SMALL_EXISTS=$(check_file_exists "$SMALL_IMAGE_FILE")
THUMB_EXISTS=$(check_file_exists "$THUMB_IMAGE_FILE")

# Check if Default Config (scope='default', id=0) was set instead (Common Mistake)
DEFAULT_BASE_FILE=$(get_config_value "design/watermark/image_image" "default" "0")
if [ -n "$DEFAULT_BASE_FILE" ] && [ -z "$BASE_IMAGE_FILE" ]; then
    WRONG_SCOPE_DETECTED="true"
else
    WRONG_SCOPE_DETECTED="false"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/watermark_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "scope_checked": "websites",
    "scope_id_checked": 1,
    "wrong_scope_detected": $WRONG_SCOPE_DETECTED,
    "base_image": {
        "file": "${BASE_IMAGE_FILE:-}",
        "opacity": "${BASE_IMAGE_OPACITY:-}",
        "position": "${BASE_IMAGE_POSITION:-}",
        "file_exists_on_disk": $BASE_EXISTS
    },
    "small_image": {
        "file": "${SMALL_IMAGE_FILE:-}",
        "opacity": "${SMALL_IMAGE_OPACITY:-}",
        "position": "${SMALL_IMAGE_POSITION:-}",
        "file_exists_on_disk": $SMALL_EXISTS
    },
    "thumbnail_image": {
        "file": "${THUMB_IMAGE_FILE:-}",
        "opacity": "${THUMB_IMAGE_OPACITY:-}",
        "position": "${THUMB_IMAGE_POSITION:-}",
        "file_exists_on_disk": $THUMB_EXISTS
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/watermark_result.json

echo ""
cat /tmp/watermark_result.json
echo ""
echo "=== Export Complete ==="