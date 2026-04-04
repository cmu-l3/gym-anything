#!/bin/bash
set -e
echo "=== Setting up Count Points in Polygons task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

DATA_DIR="/home/ga/GIS_Data"
NE_DIR="$DATA_DIR/natural_earth"
EXPORT_DIR="$DATA_DIR/exports"

# Create directories
mkdir -p "$NE_DIR" "$EXPORT_DIR"

# Download Natural Earth 110m countries if missing
if [ ! -f "$NE_DIR/ne_110m_admin_0_countries.shp" ]; then
    echo "Downloading Natural Earth 110m countries..."
    # Try multiple mirrors
    URLS=(
        "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip"
        "https://naturalearth.s3.amazonaws.com/110m_cultural/ne_110m_admin_0_countries.zip"
    )
    for url in "${URLS[@]}"; do
        if wget -q --timeout=30 -O /tmp/ne_countries.zip "$url"; then
            echo "Downloaded countries from $url"
            break
        fi
    done
    
    if [ -f /tmp/ne_countries.zip ]; then
        unzip -o /tmp/ne_countries.zip -d "$NE_DIR/" 2>/dev/null || true
        rm -f /tmp/ne_countries.zip
    else
        echo "WARNING: Failed to download countries data"
    fi
fi

# Download Natural Earth 110m populated places if missing
if [ ! -f "$NE_DIR/ne_110m_populated_places.shp" ]; then
    echo "Downloading Natural Earth 110m populated places..."
    URLS=(
        "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_populated_places.zip"
        "https://naturalearth.s3.amazonaws.com/110m_cultural/ne_110m_populated_places.zip"
    )
    for url in "${URLS[@]}"; do
        if wget -q --timeout=30 -O /tmp/ne_places.zip "$url"; then
            echo "Downloaded places from $url"
            break
        fi
    done

    if [ -f /tmp/ne_places.zip ]; then
        unzip -o /tmp/ne_places.zip -d "$NE_DIR/" 2>/dev/null || true
        rm -f /tmp/ne_places.zip
    else
        echo "WARNING: Failed to download populated places data"
    fi
fi

# Verify data files exist
echo "Checking data files..."
ls -la "$NE_DIR"/ne_110m_admin_0_countries.* 2>/dev/null || echo "WARNING: Countries data missing!"
ls -la "$NE_DIR"/ne_110m_populated_places.* 2>/dev/null || echo "WARNING: Places data missing!"

# Set permissions
chown -R ga:ga "$DATA_DIR"

# Remove any pre-existing output to ensure clean state
rm -f "$EXPORT_DIR/countries_with_place_count.geojson"
rm -f "$EXPORT_DIR/countries_place_count.geojson"

# Kill any existing QGIS instances
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis --nologo --noplugins > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS window
if wait_for_window "QGIS" 40; then
    echo "QGIS started successfully"
    
    # Maximize and focus QGIS
    sleep 2
    WID=$(get_qgis_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
else
    echo "WARNING: QGIS window not found"
fi

# Dismiss any startup dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Natural Earth data in: $NE_DIR"
echo "Expected output: $EXPORT_DIR/countries_with_place_count.geojson"