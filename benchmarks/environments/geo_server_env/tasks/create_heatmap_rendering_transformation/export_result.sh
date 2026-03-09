#!/bin/bash
echo "=== Exporting create_heatmap_rendering_transformation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check Output Image
OUTPUT_PATH="/home/ga/heatmap_output.png"
IMG_EXISTS="false"
IMG_SIZE="0"
IMG_WIDTH="0"
IMG_HEIGHT="0"
IMG_COLORS="0"
IMG_FORMAT=""
IS_ERROR_IMG="false"

if [ -f "$OUTPUT_PATH" ]; then
    IMG_EXISTS="true"
    IMG_SIZE=$(stat -c %s "$OUTPUT_PATH")
    
    # Use ImageMagick to analyze
    IDENTIFY_OUT=$(identify -format "%m|%w|%h|%k" "$OUTPUT_PATH" 2>/dev/null)
    if [ -n "$IDENTIFY_OUT" ]; then
        IMG_FORMAT=$(echo "$IDENTIFY_OUT" | cut -d'|' -f1)
        IMG_WIDTH=$(echo "$IDENTIFY_OUT" | cut -d'|' -f2)
        IMG_HEIGHT=$(echo "$IDENTIFY_OUT" | cut -d'|' -f3)
        IMG_COLORS=$(echo "$IDENTIFY_OUT" | cut -d'|' -f4)
    fi

    # Check if it's actually an XML error saved as PNG
    if grep -q "ServiceException" "$OUTPUT_PATH" 2>/dev/null || grep -q "<?xml" "$OUTPUT_PATH" 2>/dev/null; then
        IS_ERROR_IMG="true"
    fi
fi

# 2. Check Style Existence and Content
EXPECTED_STYLE="heatmap_population"
STYLE_FOUND="false"
STYLE_HAS_HEATMAP="false"
STYLE_HAS_POP_MAX="false"
STYLE_HAS_COLORMAP="false"
STYLE_IN_WORKSPACE="false"

# Check ne workspace specific first
STYLE_CHECK=$(gs_rest_get "workspaces/ne/styles/${EXPECTED_STYLE}.sld")
if echo "$STYLE_CHECK" | grep -q "No such style"; then
    # Try global/cite
    STYLE_CHECK=$(gs_rest_get "styles/${EXPECTED_STYLE}.sld")
fi

if [ -n "$STYLE_CHECK" ] && ! echo "$STYLE_CHECK" | grep -q "No such style"; then
    STYLE_FOUND="true"
    
    # Check content keywords
    if echo "$STYLE_CHECK" | grep -qi "vec:Heatmap\|Heatmap"; then
        STYLE_HAS_HEATMAP="true"
    fi
    if echo "$STYLE_CHECK" | grep -qi "pop_max"; then
        STYLE_HAS_POP_MAX="true"
    fi
    if echo "$STYLE_CHECK" | grep -qi "ColorMap"; then
        STYLE_HAS_COLORMAP="true"
    fi
fi

# 3. Check Layer Association
LAYER_ASSOCIATED="false"
LAYER_INFO=$(gs_rest_get "layers/ne:ne_populated_places.json")
if [ -n "$LAYER_INFO" ]; then
    # Check default style
    DEF_STYLE=$(echo "$LAYER_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))" 2>/dev/null)
    if [ "$DEF_STYLE" == "$EXPECTED_STYLE" ] || [ "$DEF_STYLE" == "ne:$EXPECTED_STYLE" ]; then
        LAYER_ASSOCIATED="true"
    else
        # Check alternate styles
        ALT_STYLES=$(echo "$LAYER_INFO" | python3 -c "
import sys,json
d=json.load(sys.stdin)
styles = d.get('layer',{}).get('styles',{}).get('style',[])
if not isinstance(styles, list): styles = [styles]
for s in styles: print(s.get('name',''))
" 2>/dev/null)
        if echo "$ALT_STYLES" | grep -q "$EXPECTED_STYLE"; then
            LAYER_ASSOCIATED="true"
        fi
    fi
fi

# 4. Check GUI Interaction
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "image_exists": $IMG_EXISTS,
    "image_size": $IMG_SIZE,
    "image_width": $IMG_WIDTH,
    "image_height": $IMG_HEIGHT,
    "image_colors": $IMG_COLORS,
    "image_format": "$IMG_FORMAT",
    "is_error_image": $IS_ERROR_IMG,
    "style_found": $STYLE_FOUND,
    "style_has_heatmap": $STYLE_HAS_HEATMAP,
    "style_has_pop_max": $STYLE_HAS_POP_MAX,
    "style_has_colormap": $STYLE_HAS_COLORMAP,
    "layer_associated": $LAYER_ASSOCIATED,
    "gui_interaction_detected": $GUI_INTERACTION,
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/create_heatmap_result.json"

echo "=== Export complete ==="