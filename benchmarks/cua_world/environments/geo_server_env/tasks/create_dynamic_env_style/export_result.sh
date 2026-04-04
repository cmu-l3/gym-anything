#!/bin/bash
echo "=== Exporting create_dynamic_env_style result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot of the agent's screen
take_screenshot /tmp/task_end_screenshot.png

# ==============================================================================
# CONFIGURATION
# ==============================================================================
WORKSPACE="ne"
LAYER="ne_countries"
STYLE="dynamic_country"
PARAM="target_country"
OUTPUT_FILE="/home/ga/highlight_brazil.png"

# ==============================================================================
# CHECK 1: Static File / Resource Checks
# ==============================================================================

# Check if output file exists and was created during task
OUTPUT_EXISTS="false"
OUTPUT_CREATED_DURING="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING="true"
    fi
fi

# Check if Style Exists via REST
STYLE_EXISTS="false"
STYLE_CONTENT=""
HTTP_CODE=$(gs_rest_status "workspaces/$WORKSPACE/styles/$STYLE.sld")
if [ "$HTTP_CODE" = "200" ]; then
    STYLE_EXISTS="true"
    STYLE_CONTENT=$(gs_rest_get_xml "workspaces/$WORKSPACE/styles/$STYLE.sld")
fi

# Check if Style uses 'env' function and 'target_country'
HAS_ENV_FUNC="false"
HAS_PARAM_NAME="false"
if [ "$STYLE_EXISTS" = "true" ]; then
    if echo "$STYLE_CONTENT" | grep -q "env\|environment"; then
        HAS_ENV_FUNC="true"
    fi
    if echo "$STYLE_CONTENT" | grep -q "$PARAM"; then
        HAS_PARAM_NAME="true"
    fi
fi

# Check if Style is associated with Layer
LAYER_ASSOCIATED="false"
LAYER_JSON=$(gs_rest_get "layers/$WORKSPACE:$LAYER.json")
if echo "$LAYER_JSON" | grep -q "\"name\":\"$STYLE\""; then
    LAYER_ASSOCIATED="true"
elif echo "$LAYER_JSON" | grep -q "\"name\":\"$WORKSPACE:$STYLE\""; then
    LAYER_ASSOCIATED="true"
fi

# ==============================================================================
# CHECK 2: Dynamic Rendering Verification (Anti-Gaming)
# ==============================================================================
# We perform WMS requests locally inside the container to verify the dynamic behavior.
# We test two cases:
# Case A: env=target_country:Brazil -> Brazil should be RED, Egypt should be GRAY
# Case B: env=target_country:Egypt  -> Brazil should be GRAY, Egypt should be RED

WMS_BASE="http://localhost:8080/geoserver/$WORKSPACE/wms?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&FORMAT=image/png&WIDTH=800&HEIGHT=400&SRS=EPSG:4326&BBOX=-180,-90,180,90&LAYERS=$WORKSPACE:$LAYER&STYLES=$WORKSPACE:$STYLE"

# Coordinates (X, Y) for 800x400 image
# Brazil: ~(-55, -10) -> X=277, Y=222
# Egypt:  ~(30, 26)   -> X=466, Y=142
PX_BRAZIL="277,222"
PX_EGYPT="466,142"

DYNAMIC_TEST_PASSED="false"
TEST_A_RESULT="fail"
TEST_B_RESULT="fail"

# Helper to get pixel color (hex)
get_pixel_color() {
    local img="$1"
    local coords="$2" # "x,y"
    # Convert format: imagemagick expects +x+y
    local geom="+${coords/,/+}"
    convert "$img" -crop "1x1$geom" -depth 8 txt: | grep -o '#[0-9A-F]\{6\}' | head -1
}

# Helper to check if color is reddish
is_red() {
    local hex="$1" # #RRGGBB
    if [ -z "$hex" ]; then echo "false"; return; fi
    # Extract hex components
    local r=$(printf "%d" "0x${hex:1:2}")
    local g=$(printf "%d" "0x${hex:3:2}")
    local b=$(printf "%d" "0x${hex:5:2}")
    
    # Red dominant: R > 150, G < 100, B < 100
    if [ "$r" -gt 150 ] && [ "$g" -lt 100 ] && [ "$b" -lt 100 ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Helper to check if color is grayish
is_gray() {
    local hex="$1"
    if [ -z "$hex" ]; then echo "false"; return; fi
    local r=$(printf "%d" "0x${hex:1:2}")
    local g=$(printf "%d" "0x${hex:3:2}")
    local b=$(printf "%d" "0x${hex:5:2}")
    
    # Low saturation: |R-G| < 30, |G-B| < 30
    local diff_rg=$(( r - g )); diff_rg=${diff_rg#-}
    local diff_gb=$(( g - b )); diff_gb=${diff_gb#-}
    
    if [ "$diff_rg" -lt 40 ] && [ "$diff_gb" -lt 40 ]; then
        echo "true"
    else
        echo "false"
    fi
}

if [ "$STYLE_EXISTS" = "true" ] && [ "$LAYER_ASSOCIATED" = "true" ]; then
    # --- TEST A: Target Brazil ---
    curl -s "${WMS_BASE}&ENV=${PARAM}:Brazil" -o /tmp/test_brazil.png
    
    COL_BRAZIL_A=$(get_pixel_color /tmp/test_brazil.png $PX_BRAZIL)
    COL_EGYPT_A=$(get_pixel_color /tmp/test_brazil.png $PX_EGYPT)
    
    IS_RED_BRAZIL_A=$(is_red "$COL_BRAZIL_A")
    IS_GRAY_EGYPT_A=$(is_gray "$COL_EGYPT_A")
    
    if [ "$IS_RED_BRAZIL_A" = "true" ] && [ "$IS_GRAY_EGYPT_A" = "true" ]; then
        TEST_A_RESULT="pass"
    fi

    # --- TEST B: Target Egypt ---
    curl -s "${WMS_BASE}&ENV=${PARAM}:Egypt" -o /tmp/test_egypt.png
    
    COL_BRAZIL_B=$(get_pixel_color /tmp/test_egypt.png $PX_BRAZIL)
    COL_EGYPT_B=$(get_pixel_color /tmp/test_egypt.png $PX_EGYPT)
    
    IS_GRAY_BRAZIL_B=$(is_gray "$COL_BRAZIL_B")
    IS_RED_EGYPT_B=$(is_red "$COL_EGYPT_B")
    
    if [ "$IS_GRAY_BRAZIL_B" = "true" ] && [ "$IS_RED_EGYPT_B" = "true" ]; then
        TEST_B_RESULT="pass"
    fi

    # Final Dynamic Check
    if [ "$TEST_A_RESULT" = "pass" ] && [ "$TEST_B_RESULT" = "pass" ]; then
        DYNAMIC_TEST_PASSED="true"
    fi
fi

# ==============================================================================
# JSON EXPORT
# ==============================================================================

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_created_during_task": $OUTPUT_CREATED_DURING,
    "style_exists": $STYLE_EXISTS,
    "has_env_func": $HAS_ENV_FUNC,
    "has_param_name": $HAS_PARAM_NAME,
    "layer_associated": $LAYER_ASSOCIATED,
    "dynamic_test_passed": $DYNAMIC_TEST_PASSED,
    "test_debug": {
        "test_a_brazil_color": "$COL_BRAZIL_A",
        "test_a_egypt_color": "$COL_EGYPT_A",
        "test_b_brazil_color": "$COL_BRAZIL_B",
        "test_b_egypt_color": "$COL_EGYPT_B"
    },
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/task_result.json"

echo "=== Export complete ==="