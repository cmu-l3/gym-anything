#!/bin/bash
echo "=== Exporting style_calculated_geometry_area result ==="

source /workspace/scripts/task_utils.sh

# Record export timestamp
date +%s > /tmp/export_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check if Map Image exists
OUTPUT_IMG="/home/ga/area_map.png"
IMG_EXISTS="false"
IMG_SIZE="0"
IMG_VALID="false"

if [ -f "$OUTPUT_IMG" ]; then
    IMG_EXISTS="true"
    IMG_SIZE=$(stat -c %s "$OUTPUT_IMG")
    
    # Check if created during task
    IMG_MTIME=$(stat -c %Y "$OUTPUT_IMG")
    if [ "$IMG_MTIME" -gt "$TASK_START" ]; then
        IMG_CREATED_DURING_TASK="true"
    else
        IMG_CREATED_DURING_TASK="false"
    fi
    
    # Check validity
    if identify "$OUTPUT_IMG" >/dev/null 2>&1; then
        IMG_VALID="true"
        IMG_DIMS=$(identify -format "%wx%h" "$OUTPUT_IMG")
    else
        IMG_DIMS="unknown"
    fi
else
    IMG_CREATED_DURING_TASK="false"
    IMG_DIMS=""
fi

# 2. Check Style Existence and Content
STYLE_NAME="area_classification"
WORKSPACE="ne"
STYLE_FOUND="false"
SLD_CONTENT=""
HAS_AREA_FUNCTION="false"
HAS_THRESHOLD="false"
HAS_RED="false"
HAS_GRAY="false"

# Check existence via REST
HTTP_CODE=$(gs_rest_status "workspaces/${WORKSPACE}/styles/${STYLE_NAME}.json")

if [ "$HTTP_CODE" = "200" ]; then
    STYLE_FOUND="true"
    # Get SLD content
    SLD_CONTENT=$(gs_rest_get_xml "workspaces/${WORKSPACE}/styles/${STYLE_NAME}.sld")
    
    # Analyze SLD Content (using Python for robust checking)
    ANALYSIS=$(echo "$SLD_CONTENT" | python3 -c "
import sys, re

sld = sys.stdin.read()
# Remove namespaces for easier regex
clean_sld = re.sub(r'xmlns:?\w*=\"[^\"]*\"', '', sld)

results = []

# Check for area function: ogc:Function name='area'
if re.search(r'<[^>]*Function[^>]*name=[\"\']area[\"\']', clean_sld, re.IGNORECASE):
    results.append('HAS_AREA=true')
else:
    results.append('HAS_AREA=false')

# Check for threshold 15.0 or 15
if re.search(r'<[^>]*Literal[^>]*>15(\.0?)?<', clean_sld):
    results.append('HAS_THRESHOLD=true')
else:
    results.append('HAS_THRESHOLD=false')

# Check for Red (#FF0000)
if re.search(r'#FF0000', clean_sld, re.IGNORECASE):
    results.append('HAS_RED=true')
else:
    results.append('HAS_RED=false')

# Check for Gray (#AAAAAA)
if re.search(r'#AAAAAA', clean_sld, re.IGNORECASE):
    results.append('HAS_GRAY=true')
else:
    results.append('HAS_GRAY=false')

print(';'.join(results))
")
    
    eval "$ANALYSIS"
    HAS_AREA_FUNCTION=$HAS_AREA
    HAS_THRESHOLD=$HAS_THRESHOLD
    HAS_RED=$HAS_RED
    HAS_GRAY=$HAS_GRAY
fi

# 3. Check Layer Assignment
LAYER_NAME="ne_countries"
DEFAULT_STYLE=""
LAYER_ASSIGNED="false"

LAYER_INFO=$(gs_rest_get "layers/${WORKSPACE}:${LAYER_NAME}.json")
if [ -n "$LAYER_INFO" ]; then
    DEFAULT_STYLE=$(echo "$LAYER_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))" 2>/dev/null)
    
    # Default style might be returned as "workspace:style" or just "style"
    if [ "$DEFAULT_STYLE" = "$STYLE_NAME" ] || [ "$DEFAULT_STYLE" = "${WORKSPACE}:${STYLE_NAME}" ]; then
        LAYER_ASSIGNED="true"
    fi
fi

# 4. GUI Interaction Check
GUI_INTERACTION=$(check_gui_interaction)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "img_exists": $IMG_EXISTS,
    "img_valid": $IMG_VALID,
    "img_created_during_task": $IMG_CREATED_DURING_TASK,
    "img_dims": "$(json_escape "$IMG_DIMS")",
    "style_found": $STYLE_FOUND,
    "style_name": "$STYLE_NAME",
    "has_area_function": $HAS_AREA_FUNCTION,
    "has_threshold": $HAS_THRESHOLD,
    "has_red": $HAS_RED,
    "has_gray": $HAS_GRAY,
    "layer_assigned": $LAYER_ASSIGNED,
    "default_style_found": "$(json_escape "$DEFAULT_STYLE")",
    "gui_interaction_detected": $GUI_INTERACTION,
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/style_calculated_geometry_area_result.json"

echo "=== Export complete ==="