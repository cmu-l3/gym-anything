#!/bin/bash
echo "=== Exporting optimize_label_placement result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Output Image
OUTPUT_PATH="/home/ga/places_optimized.png"
IMAGE_EXISTS="false"
IMAGE_SIZE="0"
IMAGE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    IMAGE_EXISTS="true"
    IMAGE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    IMAGE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$IMAGE_MTIME" -ge "$TASK_START" ]; then
        IMAGE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Style Existence and Content
EXPECTED_STYLE="optimized_places"
STYLE_FOUND="false"
STYLE_WORKSPACE="ne" # We expect it in 'ne', but check generic if missing
STYLE_SLD=""

# Check specific workspace first
STATUS=$(gs_rest_status "workspaces/ne/styles/${EXPECTED_STYLE}.json")
if [ "$STATUS" = "200" ]; then
    STYLE_FOUND="true"
    # Fetch SLD content
    STYLE_SLD=$(gs_rest_get_xml "workspaces/ne/styles/${EXPECTED_STYLE}.sld")
else
    # Check global
    STATUS=$(gs_rest_status "styles/${EXPECTED_STYLE}.json")
    if [ "$STATUS" = "200" ]; then
        STYLE_FOUND="true"
        STYLE_WORKSPACE="global"
        STYLE_SLD=$(gs_rest_get_xml "styles/${EXPECTED_STYLE}.sld")
    fi
fi

# 3. Parse SLD for VendorOptions using Python
# We extract the specific VendorOptions we care about
VENDOR_OPTIONS_JSON="{}"
if [ "$STYLE_FOUND" = "true" ] && [ -n "$STYLE_SLD" ]; then
    VENDOR_OPTIONS_JSON=$(echo "$STYLE_SLD" | python3 -c "
import sys, xml.etree.ElementTree as ET, json
try:
    sld = sys.stdin.read()
    # Remove XML declaration if present to avoid parsing issues
    if sld.strip().startswith('<?xml'):
        sld = sld.split('?>', 1)[1]
    
    # Simple string search if XML parsing is brittle with namespaces
    # But let's try to find keys
    options = {}
    
    # Method 1: String parsing (more robust against namespace weirdness in SLD versions)
    import re
    # Look for <VendorOption name=\"KEY\">VALUE</VendorOption>
    matches = re.findall(r'<VendorOption\s+name=[\"\']([\w]+)[\"\']>([^<]+)</VendorOption>', sld)
    for key, val in matches:
        options[key] = val.strip()
        
    print(json.dumps(options))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null)
fi

# 4. Check Layer Configuration (Default Style)
LAYER_DEFAULT_STYLE=""
LAYER_NAME="ne_populated_places"
LAYER_WS="ne"

LAYER_JSON=$(gs_rest_get "workspaces/${LAYER_WS}/layers/${LAYER_NAME}.json")
LAYER_DEFAULT_STYLE=$(echo "$LAYER_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('layer', {}).get('defaultStyle', {}).get('name', ''))
except:
    print('')
" 2>/dev/null)

# 5. Check GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "image_exists": ${IMAGE_EXISTS},
    "image_created_during_task": ${IMAGE_CREATED_DURING_TASK},
    "image_size": ${IMAGE_SIZE},
    "style_found": ${STYLE_FOUND},
    "style_workspace": "$(json_escape "$STYLE_WORKSPACE")",
    "vendor_options": ${VENDOR_OPTIONS_JSON:-{}},
    "layer_default_style": "$(json_escape "$LAYER_DEFAULT_STYLE")",
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/optimize_label_placement_result.json"

echo "=== Export complete ==="