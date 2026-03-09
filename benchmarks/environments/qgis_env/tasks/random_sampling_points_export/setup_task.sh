#!/bin/bash
set -e
echo "=== Setting up Random Sampling Points task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure exports directory exists and is clean
mkdir -p /home/ga/GIS_Data/exports
rm -f /home/ga/GIS_Data/exports/sampling_points.geojson
rm -f /home/ga/GIS_Data/exports/sampling_coordinates.csv

# Download Natural Earth 110m countries dataset if not already present
NE_URL="https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip"
NE_ZIP="/tmp/ne_110m_countries.zip"
NE_DIR="/tmp/ne_countries"

if [ ! -f "/home/ga/GIS_Data/european_countries.geojson" ]; then
    echo "Preparing input data..."
    
    # Download
    if [ ! -f "$NE_ZIP" ]; then
        echo "Downloading dataset..."
        wget -q --timeout=60 -O "$NE_ZIP" "$NE_URL" || {
            echo "Primary download failed, trying mirror..."
            wget -q --timeout=60 -O "$NE_ZIP" \
                "https://github.com/nvkelso/natural-earth-vector/raw/master/zips/ne_110m_admin_0_countries.zip"
        }
    fi

    # Extract
    mkdir -p "$NE_DIR"
    unzip -o -q "$NE_ZIP" -d "$NE_DIR"

    # Find shapefile
    SHP_FILE=$(find "$NE_DIR" -name "*.shp" | head -1)
    
    if [ -n "$SHP_FILE" ]; then
        echo "Filtering for Austria, Switzerland, Czechia..."
        # Use ogr2ogr to filter specific countries
        ogr2ogr -f GeoJSON \
            -where "ADMIN IN ('Austria', 'Switzerland', 'Czechia', 'Czech Republic')" \
            /home/ga/GIS_Data/european_countries.geojson \
            "$SHP_FILE"
            
        # Ensure we have data
        if [ ! -s "/home/ga/GIS_Data/european_countries.geojson" ]; then
            echo "ERROR: Filtering failed, creating fallback data"
            # Fallback simple polygons if download/filter fails
            cat > /home/ga/GIS_Data/european_countries.geojson << 'EOF'
{
"type": "FeatureCollection",
"name": "european_countries",
"crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
"features": [
{ "type": "Feature", "properties": { "ADMIN": "Austria" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ 16.9, 48.1 ], [ 16.5, 47.9 ], [ 16.0, 46.8 ], [ 14.5, 46.4 ], [ 13.8, 46.6 ], [ 12.2, 47.1 ], [ 10.5, 46.8 ], [ 9.5, 47.3 ], [ 9.7, 47.5 ], [ 10.9, 47.4 ], [ 12.6, 47.6 ], [ 13.0, 48.0 ], [ 12.9, 48.2 ], [ 13.8, 48.8 ], [ 15.0, 49.0 ], [ 15.2, 48.8 ], [ 16.9, 48.6 ], [ 16.9, 48.1 ] ] ] } },
{ "type": "Feature", "properties": { "ADMIN": "Switzerland" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ 9.5, 47.5 ], [ 9.6, 47.3 ], [ 9.5, 47.3 ], [ 10.5, 46.8 ], [ 10.5, 46.5 ], [ 9.0, 45.8 ], [ 7.0, 45.9 ], [ 6.0, 46.2 ], [ 6.1, 46.4 ], [ 6.8, 47.3 ], [ 7.6, 47.6 ], [ 8.7, 47.7 ], [ 9.5, 47.5 ] ] ] } },
{ "type": "Feature", "properties": { "ADMIN": "Czechia" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ 14.8, 50.9 ], [ 12.1, 50.2 ], [ 12.3, 50.0 ], [ 13.5, 49.5 ], [ 13.8, 48.8 ], [ 16.9, 48.6 ], [ 16.9, 48.8 ], [ 17.5, 49.5 ], [ 18.9, 49.5 ], [ 18.5, 49.8 ], [ 18.2, 49.9 ], [ 17.0, 50.3 ], [ 16.2, 50.4 ], [ 15.0, 51.0 ], [ 14.8, 50.9 ] ] ] } }
]
}
EOF
        fi
    else
        echo "ERROR: Shapefile not found in download"
        exit 1
    fi
    
    # Clean up download
    rm -rf "$NE_DIR" "$NE_ZIP"
fi

# Set permissions
chown -R ga:ga /home/ga/GIS_Data/
chmod 644 /home/ga/GIS_Data/european_countries.geojson

# Kill any existing QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis --nologo --noplugins > /tmp/qgis_task.log 2>&1 &"

# Wait for window
wait_for_window "QGIS" 60

# Maximize
DISPLAY=:1 wmctrl -r "QGIS" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="