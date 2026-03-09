#!/bin/bash
# Enable error handling but continue on non-critical errors
set -o pipefail

# Ensure we always create a result file even on failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result due to script failure"
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_path": "",
    "file_size": 0,
    "file_modified": "0",
    "file_hash": "",
    "file_created_during_task": false,
    "task_start_time": 0,
    "task_end_time": 0,
    "initial_ggb_count": 0,
    "current_ggb_count": 0,
    "num_points": 0,
    "num_segments": 0,
    "num_polygons": 0,
    "num_circles": 0,
    "timestamp": "",
    "error": "Export script failed to complete normally"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Source task_utils.sh with fallback if not found
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    echo "WARNING: task_utils.sh not found, using inline functions"
    # Define minimal inline functions if source file not available
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
    is_geogebra_running() { pgrep -f "geogebra" > /dev/null 2>&1; }
    close_geogebra() { pkill -f "geogebra" 2>/dev/null || true; }
fi

echo "=== Exporting Construct Equilateral Triangle Result ==="

# Get task timing information for validation
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END_TIME=$(date +%s)

# Check for the expected GeoGebra file
PROJECT_DIR="/home/ga/Documents/GeoGebra/projects"
EXPECTED_FILE="$PROJECT_DIR/equilateral_triangle.ggb"

# Initialize result variables
FILE_FOUND="false"
FILE_PATH=""
FILE_SIZE=0
FILE_MODIFIED=""
FILE_CREATED_DURING_TASK="false"
FILE_HASH=""

if [ -f "$EXPECTED_FILE" ]; then
    echo "Found expected file: $EXPECTED_FILE"
    FILE_FOUND="true"
    FILE_PATH="$EXPECTED_FILE"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")
    FILE_MODIFIED=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")

    # Calculate file hash for integrity check
    FILE_HASH=$(sha256sum "$EXPECTED_FILE" 2>/dev/null | cut -d' ' -f1 || echo "")

    # Check if file was modified during task window
    if [ "$TASK_START_TIME" != "0" ] && [ "$FILE_MODIFIED" -ge "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "File was created/modified during task (after task start: $TASK_START_TIME)"
    else
        echo "WARNING: File modification time ($FILE_MODIFIED) is before task start ($TASK_START_TIME)"
    fi

    # Copy for verification
    cp "$EXPECTED_FILE" /tmp/geogebra_result.ggb 2>/dev/null || true
else
    echo "Expected file not found, searching for recently created .ggb files..."

    # Look for any recently created .ggb file
    RECENT_FILE=$(find "$PROJECT_DIR" /home/ga/Documents/GeoGebra -name "*.ggb" -mmin -10 2>/dev/null | head -1)

    if [ -n "$RECENT_FILE" ]; then
        echo "Found recent GeoGebra file: $RECENT_FILE"
        FILE_FOUND="true"
        FILE_PATH="$RECENT_FILE"
        FILE_SIZE=$(stat -c%s "$RECENT_FILE" 2>/dev/null || echo "0")
        FILE_MODIFIED=$(stat -c%Y "$RECENT_FILE" 2>/dev/null || echo "0")

        # Calculate file hash for integrity check
        FILE_HASH=$(sha256sum "$RECENT_FILE" 2>/dev/null | cut -d' ' -f1 || echo "")

        # Check if file was modified during task window
        if [ "$TASK_START_TIME" != "0" ] && [ "$FILE_MODIFIED" -ge "$TASK_START_TIME" ]; then
            FILE_CREATED_DURING_TASK="true"
            echo "File was created/modified during task (after task start: $TASK_START_TIME)"
        else
            echo "WARNING: File modification time ($FILE_MODIFIED) is before task start ($TASK_START_TIME)"
        fi

        # Copy for verification
        cp "$RECENT_FILE" /tmp/geogebra_result.ggb 2>/dev/null || true
    fi
fi

# Extract GeoGebra XML from .ggb file (it's a ZIP archive)
GGB_XML=""
if [ -f "/tmp/geogebra_result.ggb" ]; then
    echo "Extracting GeoGebra XML..."
    cd /tmp
    rm -rf /tmp/ggb_extract 2>/dev/null || true
    mkdir -p /tmp/ggb_extract
    unzip -q /tmp/geogebra_result.ggb -d /tmp/ggb_extract 2>/dev/null || true

    if [ -f "/tmp/ggb_extract/geogebra.xml" ]; then
        # Copy the XML for verification
        cp /tmp/ggb_extract/geogebra.xml /tmp/geogebra_construction.xml 2>/dev/null || true

        # Extract basic info from XML
        # Note: grep -c returns exit code 1 when count is 0, but still outputs "0"
        # We use a subshell with true to suppress the exit code issue
        NUM_POINTS=$(grep -c '<element type="point"' /tmp/ggb_extract/geogebra.xml 2>/dev/null; true)
        NUM_SEGMENTS=$(grep -c '<element type="segment"' /tmp/ggb_extract/geogebra.xml 2>/dev/null; true)
        NUM_POLYGONS=$(grep -c '<element type="polygon"' /tmp/ggb_extract/geogebra.xml 2>/dev/null; true)
        NUM_CIRCLES=$(grep -c '<element type="circle"' /tmp/ggb_extract/geogebra.xml 2>/dev/null; true)

        # Ensure variables are set even if grep fails
        NUM_POINTS=${NUM_POINTS:-0}
        NUM_SEGMENTS=${NUM_SEGMENTS:-0}
        NUM_POLYGONS=${NUM_POLYGONS:-0}
        NUM_CIRCLES=${NUM_CIRCLES:-0}

        echo "Construction contains:"
        echo "  - Points: $NUM_POINTS"
        echo "  - Segments: $NUM_SEGMENTS"
        echo "  - Polygons: $NUM_POLYGONS"
        echo "  - Circles: $NUM_CIRCLES"
    else
        # Set defaults if XML not found
        NUM_POINTS=0
        NUM_SEGMENTS=0
        NUM_POLYGONS=0
        NUM_CIRCLES=0
        echo "Warning: geogebra.xml not found in extracted archive"
    fi
else
    # Set defaults if ggb file not available
    NUM_POINTS=0
    NUM_SEGMENTS=0
    NUM_POLYGONS=0
    NUM_CIRCLES=0
fi

# Take final screenshot (redirect any output to avoid contaminating variables)
take_screenshot /tmp/geogebra_final_screenshot.png > /dev/null 2>&1 || true

# Get initial count (ensure no extra output)
INITIAL_COUNT=$(cat /tmp/initial_ggb_count 2>/dev/null || echo "0")
INITIAL_COUNT=${INITIAL_COUNT:-0}
CURRENT_COUNT=$(find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l || echo "0")
CURRENT_COUNT=${CURRENT_COUNT:-0}

# Close GeoGebra (suppress any output)
if is_geogebra_running > /dev/null 2>&1; then
    close_geogebra ga > /dev/null 2>&1
fi

# Create JSON result using temp file pattern
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_found": $FILE_FOUND,
    "file_path": "$FILE_PATH",
    "file_size": $FILE_SIZE,
    "file_modified": "$FILE_MODIFIED",
    "file_hash": "$FILE_HASH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "task_start_time": $TASK_START_TIME,
    "task_end_time": $TASK_END_TIME,
    "initial_ggb_count": $INITIAL_COUNT,
    "current_ggb_count": $CURRENT_COUNT,
    "num_points": ${NUM_POINTS:-0},
    "num_segments": ${NUM_SEGMENTS:-0},
    "num_polygons": ${NUM_POLYGONS:-0},
    "num_circles": ${NUM_CIRCLES:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="
