#!/bin/bash
echo "=== Exporting create_multiscale_geometry_style result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_end_screenshot.png

# ==============================================================================
# 1. CHECK STYLE EXISTENCE AND CONTENT
# ==============================================================================
STYLE_NAME="country_semantic_zoom"
WORKSPACE="ne"
STYLE_FOUND="false"
STYLE_CONTENT=""

# Check if style exists in workspace 'ne'
STATUS=$(gs_rest_status "workspaces/${WORKSPACE}/styles/${STYLE_NAME}.json")
if [ "$STATUS" = "200" ]; then
    STYLE_FOUND="true"
    # Get the SLD content
    STYLE_CONTENT=$(gs_rest_get_xml "workspaces/${WORKSPACE}/styles/${STYLE_NAME}.sld")
fi

# Fallback: check global styles if not found in workspace
if [ "$STYLE_FOUND" = "false" ]; then
    STATUS=$(gs_rest_status "styles/${STYLE_NAME}.json")
    if [ "$STATUS" = "200" ]; then
        STYLE_FOUND="true"
        STYLE_CONTENT=$(gs_rest_get_xml "styles/${STYLE_NAME}.sld")
    fi
fi

# Save SLD to temp file for verifier analysis
if [ -n "$STYLE_CONTENT" ]; then
    echo "$STYLE_CONTENT" > /tmp/extracted_style.sld
fi

# ==============================================================================
# 2. CHECK LAYER ASSOCIATION
# ==============================================================================
LAYER_NAME="ne_countries"
LAYER_DEFAULT_STYLE=""
LAYER_CHECK_JSON=$(gs_rest_get "workspaces/ne/layers/${LAYER_NAME}.json")

# Extract default style name using python
LAYER_DEFAULT_STYLE=$(echo "$LAYER_CHECK_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    style = d.get('layer', {}).get('defaultStyle', {}).get('name', '')
    # Handle workspace prefix if present (ne:style_name)
    if ':' in style:
        style = style.split(':')[1]
    print(style)
except:
    print('')
" 2>/dev/null)

STYLE_APPLIED="false"
if [ "$LAYER_DEFAULT_STYLE" = "$STYLE_NAME" ]; then
    STYLE_APPLIED="true"
fi

# ==============================================================================
# 3. GENERATE WMS RENDER PROOFS
# ==============================================================================
# We need to prove that the style renders differently at different scales.
# Scale denominator ~= Map Scale.
# 35M threshold.

# Render 1: Zoomed In (Scale ~ 1:10M) -> Should be Polygons
# BBox for a small area (e.g., France)
BBOX_IN="-5,42,10,51"
WIDTH_IN=800
HEIGHT_IN=600
# Calculating scale: roughly fits 15 degrees in 800px... approx 1:10M-1:15M

# Render 2: Zoomed Out (Scale ~ 1:100M) -> Should be Points
# BBox for World
BBOX_OUT="-180,-90,180,90"
WIDTH_OUT=800
HEIGHT_OUT=400

# Function to fetch map
fetch_wms_image() {
    local bbox=$1
    local width=$2
    local height=$3
    local output=$4
    
    # Force use of the specific style to verify logic even if not applied correctly
    curl -s -G "http://localhost:8080/geoserver/ne/wms" \
        --data-urlencode "service=WMS" \
        --data-urlencode "version=1.1.0" \
        --data-urlencode "request=GetMap" \
        --data-urlencode "layers=ne:${LAYER_NAME}" \
        --data-urlencode "styles=${WORKSPACE}:${STYLE_NAME}" \
        --data-urlencode "bbox=${bbox}" \
        --data-urlencode "width=${width}" \
        --data-urlencode "height=${height}" \
        --data-urlencode "srs=EPSG:4326" \
        --data-urlencode "format=image/png" \
        -o "$output"
}

if [ "$STYLE_FOUND" = "true" ]; then
    fetch_wms_image "$BBOX_IN" "$WIDTH_IN" "$HEIGHT_IN" "/tmp/render_zoomed_in.png"
    fetch_wms_image "$BBOX_OUT" "$WIDTH_OUT" "$HEIGHT_OUT" "/tmp/render_zoomed_out.png"
fi

# ==============================================================================
# 4. EXPORT RESULT JSON
# ==============================================================================

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "style_found": $STYLE_FOUND,
    "style_name": "$(json_escape "$STYLE_NAME")",
    "layer_default_style": "$(json_escape "$LAYER_DEFAULT_STYLE")",
    "style_applied": $STYLE_APPLIED,
    "sld_file_path": "/tmp/extracted_style.sld",
    "render_in_path": "/tmp/render_zoomed_in.png",
    "render_out_path": "/tmp/render_zoomed_out.png",
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/create_multiscale_geometry_style_result.json"

# Ensure permissions on artifacts
chmod 644 /tmp/extracted_style.sld 2>/dev/null || true
chmod 644 /tmp/render_zoomed_in.png 2>/dev/null || true
chmod 644 /tmp/render_zoomed_out.png 2>/dev/null || true

echo "=== Export complete ==="