#!/bin/bash
# Export script for configure_variation_image_style task
echo "=== Exporting configure_variation_image_style Result ==="

source /workspace/scripts/task_utils.sh

# Fallback
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check if Image Style config exists
STYLE_EXISTS="false"
STYLE_DATA=""
STYLE_CONFIG_NAME="image.style.product_main_600"

RAW_STYLE=$(drupal_db_query "SELECT data FROM config WHERE name = '$STYLE_CONFIG_NAME'")
if [ -n "$RAW_STYLE" ]; then
    STYLE_EXISTS="true"
    STYLE_DATA="$RAW_STYLE"
fi

# 2. Check Image Style Effects (Scale and Crop 600x600)
# We use Python to parse the PHP serialized blob or regex it
# PHP serialization for effects usually looks like:
# ... "id";s:20:"image_scale_and_crop"; ... "width";i:600; ... "height";i:600; ...
HAS_SCALE_CROP="false"
WIDTH_SET="0"
HEIGHT_SET="0"

if [ "$STYLE_EXISTS" = "true" ]; then
    # Use python to extract values safely
    EFFECT_INFO=$(echo "$STYLE_DATA" | python3 -c "
import sys, re
data = sys.stdin.read()
# Check for effect ID
has_effect = 'image_scale_and_crop' in data
# Extract width and height (handle integer 'i:600' or string 's:3:\"600\"')
w_match = re.search(r'\"width\";[is]:(\d+)', data)
h_match = re.search(r'\"height\";[is]:(\d+)', data)
# Fallback regex for simpler serialization
if not w_match: w_match = re.search(r'width.*?(\d+)', data)
if not h_match: h_match = re.search(r'height.*?(\d+)', data)

w = w_match.group(1) if w_match else '0'
h = h_match.group(1) if h_match else '0'

print(f'{has_effect}|{w}|{h}')
")
    
    HAS_SCALE_CROP=$(echo "$EFFECT_INFO" | cut -d'|' -f1)
    if [ "$HAS_SCALE_CROP" = "True" ]; then HAS_SCALE_CROP="true"; else HAS_SCALE_CROP="false"; fi
    WIDTH_SET=$(echo "$EFFECT_INFO" | cut -d'|' -f2)
    HEIGHT_SET=$(echo "$EFFECT_INFO" | cut -d'|' -f3)
fi

# 3. Check Product Variation Display Config
# Config name: core.entity_view_display.commerce_product_variation.default.default
# We need to see if field_images (or images) is set to use product_main_600
DISPLAY_CONFIG_NAME="core.entity_view_display.commerce_product_variation.default.default"
DISPLAY_EXISTS="false"
DISPLAY_DATA=""
DISPLAY_UPDATED="false"

RAW_DISPLAY=$(drupal_db_query "SELECT data FROM config WHERE name = '$DISPLAY_CONFIG_NAME'")
if [ -n "$RAW_DISPLAY" ]; then
    DISPLAY_EXISTS="true"
    DISPLAY_DATA="$RAW_DISPLAY"
fi

USED_STYLE=""
if [ "$DISPLAY_EXISTS" = "true" ]; then
    # Parse the display config to find the image style setting for field_images or images
    # Look for "image_style";s:16:"product_main_600" inside the field configuration
    USED_STYLE=$(echo "$DISPLAY_DATA" | python3 -c "
import sys, re
data = sys.stdin.read()
# Look for image_style setting. It might be nested.
# Pattern: \"image_style\";s:(\d+):\"(product_main_600)\"
m = re.search(r'\"image_style\";s:\d+:\"(product_main_600)\"', data)
if m:
    print(m.group(1))
else:
    print('')
")
    if [ -n "$USED_STYLE" ]; then
        DISPLAY_UPDATED="true"
    fi
fi

# Generate result JSON
cat > /tmp/task_result.json << EOF
{
    "style_exists": $STYLE_EXISTS,
    "has_scale_crop": $HAS_SCALE_CROP,
    "width": $WIDTH_SET,
    "height": $HEIGHT_SET,
    "display_config_exists": $DISPLAY_EXISTS,
    "display_updated": $DISPLAY_UPDATED,
    "used_style": "$USED_STYLE",
    "timestamp": $(date +%s)
}
EOF

echo "Result generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="