#!/bin/bash
echo "=== Exporting load_and_style_vector_layers result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi
if ! type get_qgis_window_id &>/dev/null; then
    get_qgis_window_id() { DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'qgis' | awk '{print $1; exit}'; }
fi

# Take final screenshot
take_screenshot /tmp/task_end.png

PROJECT_DIR="/home/ga/GIS_Data/projects"
EXPECTED_QGZ="$PROJECT_DIR/styled_layers.qgz"
EXPECTED_QGS="$PROJECT_DIR/styled_layers.qgs"

INITIAL_COUNT=$(cat /tmp/initial_project_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$PROJECT_DIR"/*.qgz "$PROJECT_DIR"/*.qgs 2>/dev/null | wc -l || echo "0")

# Check for expected project file
PROJECT_FOUND="false"
PROJECT_PATH=""
PROJECT_SIZE=0
PROJECT_VALID="false"
LAYER_COUNT=0
HAS_POLYGON_LAYER="false"
HAS_POINT_LAYER="false"
POLYGON_LAYER_NAME=""
POINT_LAYER_NAME=""

# Check for QGZ (preferred) or QGS
if [ -f "$EXPECTED_QGZ" ]; then
    PROJECT_FOUND="true"
    PROJECT_PATH="$EXPECTED_QGZ"
    PROJECT_SIZE=$(stat -c%s "$EXPECTED_QGZ" 2>/dev/null || echo "0")
    if file "$EXPECTED_QGZ" 2>/dev/null | grep -qi 'zip'; then
        PROJECT_VALID="true"
        # Extract QGS from QGZ to inspect layers
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"
        unzip -o "$EXPECTED_QGZ" 2>/dev/null || true
        QGS_INSIDE=$(find "$TEMP_DIR" -name "*.qgs" | head -1)
        if [ -n "$QGS_INSIDE" ]; then
            LAYER_COUNT=$(grep -c '<maplayer' "$QGS_INSIDE" 2>/dev/null || echo "0")
            if grep -qi 'sample_polygon\|sample.polygon' "$QGS_INSIDE" 2>/dev/null; then
                HAS_POLYGON_LAYER="true"
                POLYGON_LAYER_NAME=$(grep -oP '<layername>[^<]*sample[^<]*polygon[^<]*</layername>' "$QGS_INSIDE" 2>/dev/null | head -1 | sed 's/<[^>]*>//g')
            fi
            if grep -qi 'sample_points\|sample.points' "$QGS_INSIDE" 2>/dev/null; then
                HAS_POINT_LAYER="true"
                POINT_LAYER_NAME=$(grep -oP '<layername>[^<]*sample[^<]*points[^<]*</layername>' "$QGS_INSIDE" 2>/dev/null | head -1 | sed 's/<[^>]*>//g')
            fi
        fi
        rm -rf "$TEMP_DIR"
    fi
elif [ -f "$EXPECTED_QGS" ]; then
    PROJECT_FOUND="true"
    PROJECT_PATH="$EXPECTED_QGS"
    PROJECT_SIZE=$(stat -c%s "$EXPECTED_QGS" 2>/dev/null || echo "0")
    if head -1 "$EXPECTED_QGS" 2>/dev/null | grep -q '<?xml'; then
        PROJECT_VALID="true"
        LAYER_COUNT=$(grep -c '<maplayer' "$EXPECTED_QGS" 2>/dev/null || echo "0")
        if grep -qi 'sample_polygon\|sample.polygon' "$EXPECTED_QGS" 2>/dev/null; then
            HAS_POLYGON_LAYER="true"
            POLYGON_LAYER_NAME=$(grep -oP '<layername>[^<]*sample[^<]*polygon[^<]*</layername>' "$EXPECTED_QGS" 2>/dev/null | head -1 | sed 's/<[^>]*>//g')
        fi
        if grep -qi 'sample_points\|sample.points' "$EXPECTED_QGS" 2>/dev/null; then
            HAS_POINT_LAYER="true"
            POINT_LAYER_NAME=$(grep -oP '<layername>[^<]*sample[^<]*points[^<]*</layername>' "$EXPECTED_QGS" 2>/dev/null | head -1 | sed 's/<[^>]*>//g')
        fi
    fi
fi

# Also check for any project file if expected not found
if [ "$PROJECT_FOUND" = "false" ]; then
    RECENT=$(find "$PROJECT_DIR" -maxdepth 1 \( -name "*.qgs" -o -name "*.qgz" \) -mmin -10 2>/dev/null | head -1)
    if [ -n "$RECENT" ]; then
        PROJECT_PATH="$RECENT"
        PROJECT_SIZE=$(stat -c%s "$RECENT" 2>/dev/null || echo "0")
    fi
fi

# Close QGIS
if is_qgis_running; then
    WID=$(get_qgis_window_id)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    fi
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "initial_project_count": $INITIAL_COUNT,
    "current_project_count": $CURRENT_COUNT,
    "project_found": $PROJECT_FOUND,
    "project_path": "$PROJECT_PATH",
    "project_size_bytes": $PROJECT_SIZE,
    "project_valid": $PROJECT_VALID,
    "layer_count": $LAYER_COUNT,
    "has_polygon_layer": $HAS_POLYGON_LAYER,
    "has_point_layer": $HAS_POINT_LAYER,
    "polygon_layer_name": "$POLYGON_LAYER_NAME",
    "point_layer_name": "$POINT_LAYER_NAME",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="
