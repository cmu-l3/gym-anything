#!/bin/bash
echo "=== Setting up simplify_geometries_web_export task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions for utilities if not sourced correctly
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi
if ! type wait_for_window &>/dev/null; then
    wait_for_window() {
        local pattern="$1"; local timeout=${2:-30}; local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern" && return 0
            sleep 1; elapsed=$((elapsed + 1))
        done
        return 1
    }
fi

# 1. Prepare Data Directories
DATA_DIR="/home/ga/GIS_Data/natural_earth"
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$DATA_DIR"
mkdir -p "$EXPORT_DIR"

# 2. Download Natural Earth Data
SHP_FILE="$DATA_DIR/ne_50m_admin_0_countries.shp"
ZIP_FILE="$DATA_DIR/ne_50m_admin_0_countries.zip"

if [ ! -f "$SHP_FILE" ]; then
    echo "Downloading Natural Earth 50m countries data..."
    # Use curl with retry and location following
    if curl -L -o "$ZIP_FILE" "https://naciscdn.org/naturalearth/50m/cultural/ne_50m_admin_0_countries.zip"; then
        echo "Download complete. Extracting..."
        unzip -o -q "$ZIP_FILE" -d "$DATA_DIR"
        chmod 644 "$DATA_DIR"/*
        rm -f "$ZIP_FILE"
    else
        echo "ERROR: Failed to download dataset"
        # Create a fallback dummy file if download fails (to prevent immediate crash, though task will likely fail)
        touch "$SHP_FILE"
    fi
else
    echo "Data already exists."
fi

# 3. Analyze Input Data (Baseline Vertex Count)
# We use Python to count vertices in the shapefile to establish a baseline
echo "Analyzing input shapefile..."
INPUT_STATS=$(python3 << 'PYEOF'
try:
    import sys
    # Try using pyshp if available, or just estimate
    try:
        import shapefile
        sf = shapefile.Reader("/home/ga/GIS_Data/natural_earth/ne_50m_admin_0_countries.shp")
        total_points = 0
        for shape in sf.shapes():
            total_points += len(shape.points)
        print(f"{total_points}")
    except ImportError:
        # Fallback if pyshp not installed: rough estimate or specific known value for this dataset
        # The 50m dataset has approx 58,000 vertices
        print("58000")
except Exception:
    print("0")
PYEOF
)
echo "$INPUT_STATS" > /tmp/input_vertex_count.txt
echo "Baseline vertex count: $INPUT_STATS"

# 4. Clean up previous results
rm -f "$EXPORT_DIR/countries_simplified.geojson" 2>/dev/null || true
rm -f "$EXPORT_DIR/countries_simplified.json" 2>/dev/null || true

# 5. Record start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# 6. Ensure QGIS is running and clean
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS to start
sleep 5
wait_for_window "QGIS" 45
sleep 3

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "QGIS" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="