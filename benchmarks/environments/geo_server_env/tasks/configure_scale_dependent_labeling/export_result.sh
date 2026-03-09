#!/bin/bash
set -e
echo "=== Exporting configure_scale_dependent_labeling result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Task Parameters
WS="ne"
STYLE="scaled_cities"
LAYER="ne_populated_places"
GS_WMS_URL="${GS_URL}/ne/wms"

# 1. Check if Style Exists
echo "Checking style existence..."
STYLE_JSON=$(gs_rest_get "workspaces/${WS}/styles/${STYLE}.json")
STYLE_EXISTS=$(echo "$STYLE_JSON" | grep -q "\"name\":\"${STYLE}\"" && echo "true" || echo "false")

# 2. Get SLD Content (if style exists)
SLD_CONTENT=""
if [ "$STYLE_EXISTS" = "true" ]; then
    # Get XML content
    SLD_CONTENT=$(gs_rest_get_xml "workspaces/${WS}/styles/${STYLE}.sld")
fi

# 3. Check Layer Assignment
echo "Checking layer assignment..."
LAYER_JSON=$(gs_rest_get "workspaces/${WS}/layers/${LAYER}.json")
ASSIGNED_STYLE=$(echo "$LAYER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))" 2>/dev/null || echo "")

# 4. Visual Verification (WMS Generation)
# We generate two images:
# A. Zoomed Out (Global) - Scale ~ 1:140M -> Should NOT have labels (only points)
# B. Zoomed In (Regional) - Scale ~ 1:6M -> Should HAVE labels

echo "Generating verification images..."
IMG_OUT="/tmp/verify_zoomed_out.png"
IMG_IN="/tmp/verify_zoomed_in.png"

# WMS Request A: World View
wget -q "${GS_WMS_URL}?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&FORMAT=image/png&TRANSPARENT=true&STYLES=${STYLE}&LAYERS=${WS}:${LAYER}&SRS=EPSG:4326&WIDTH=1024&HEIGHT=512&BBOX=-180,-90,180,90" -O "$IMG_OUT" || echo "Failed to render zoomed out"

# WMS Request B: Europe View
wget -q "${GS_WMS_URL}?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&FORMAT=image/png&TRANSPARENT=true&STYLES=${STYLE}&LAYERS=${WS}:${LAYER}&SRS=EPSG:4326&WIDTH=1024&HEIGHT=1024&BBOX=-5,40,10,55" -O "$IMG_IN" || echo "Failed to render zoomed in"

# Analyze Images (Color Count)
# High color count implies labels (antialiased text + halo adds many colors)
# Low color count implies just points (simple geometry)
COLORS_OUT=$(identify -format "%k" "$IMG_OUT" 2>/dev/null || echo "0")
COLORS_IN=$(identify -format "%k" "$IMG_IN" 2>/dev/null || echo "0")
SIZE_OUT=$(stat -c%s "$IMG_OUT" 2>/dev/null || echo "0")
SIZE_IN=$(stat -c%s "$IMG_IN" 2>/dev/null || echo "0")

echo "Visual Stats: Out(Colors=$COLORS_OUT, Size=$SIZE_OUT) In(Colors=$COLORS_IN, Size=$SIZE_IN)"

# Escape SLD content for JSON
SLD_ESCAPED=$(json_escape "$SLD_CONTENT")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "style_exists": $STYLE_EXISTS,
    "assigned_style": "$(json_escape "$ASSIGNED_STYLE")",
    "sld_content": "$SLD_ESCAPED",
    "visual_stats": {
        "zoomed_out_colors": $COLORS_OUT,
        "zoomed_in_colors": $COLORS_IN,
        "zoomed_out_size": $SIZE_OUT,
        "zoomed_in_size": $SIZE_IN
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/task_result.json"
echo "=== Export complete ==="