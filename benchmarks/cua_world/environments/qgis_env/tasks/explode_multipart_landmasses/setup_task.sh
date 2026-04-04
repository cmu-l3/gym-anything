#!/bin/bash
set -e
echo "=== Setting up Explode Multipart Geometries task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure export directory exists
mkdir -p /home/ga/GIS_Data/exports
chown ga:ga /home/ga/GIS_Data/exports

# Remove any pre-existing output
rm -f /home/ga/GIS_Data/exports/countries_singlepart.geojson
rm -f /home/ga/GIS_Data/exports/countries_singlepart.*

# Download Natural Earth 110m countries data
NE_DIR="/home/ga/GIS_Data/ne_110m_countries"
NE_ZIP="/tmp/ne_110m_admin_0_countries.zip"

if [ ! -f "$NE_DIR/ne_110m_admin_0_countries.shp" ]; then
    echo "Downloading Natural Earth 110m countries..."
    mkdir -p "$NE_DIR"

    # Try downloading from official source
    if wget -q -O "$NE_ZIP" "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip"; then
        unzip -o -q "$NE_ZIP" -d "$NE_DIR/"
        echo "Natural Earth data extracted to $NE_DIR"
    else
        echo "WARNING: Download failed, creating fallback multipart data..."
        # Fallback: create a GeoJSON with real multipart geometries (Indonesia, Japan, Philippines)
        cat > "$NE_DIR/ne_110m_admin_0_countries.geojson" << 'FALLBACKEOF'
{
  "type": "FeatureCollection",
  "name": "ne_110m_admin_0_countries",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    {"type":"Feature","properties":{"NAME":"Indonesia","ADMIN":"Indonesia","ISO_A3":"IDN"},"geometry":{"type":"MultiPolygon","coordinates":[[[[95.0,-8.0],[95.0,-5.0],[105.0,-5.0],[105.0,-8.0],[95.0,-8.0]]],[[[110.0,-8.5],[110.0,-6.0],[115.0,-6.0],[115.0,-8.5],[110.0,-8.5]]],[[[117.0,-4.0],[117.0,-1.0],[125.0,-1.0],[125.0,-4.0],[117.0,-4.0]]]]}},
    {"type":"Feature","properties":{"NAME":"Japan","ADMIN":"Japan","ISO_A3":"JPN"},"geometry":{"type":"MultiPolygon","coordinates":[[[[129.5,31.0],[129.5,33.5],[132.0,33.5],[132.0,31.0],[129.5,31.0]]],[[[132.5,33.0],[132.5,35.5],[137.0,35.5],[137.0,33.0],[132.5,33.0]]],[[[139.0,35.0],[139.0,41.5],[145.5,41.5],[145.5,35.0],[139.0,35.0]]]]}},
    {"type":"Feature","properties":{"NAME":"Philippines","ADMIN":"Philippines","ISO_A3":"PHL"},"geometry":{"type":"MultiPolygon","coordinates":[[[[119.5,9.0],[119.5,12.5],[122.5,12.5],[122.5,9.0],[119.5,9.0]]],[[[121.0,13.0],[121.0,18.5],[124.0,18.5],[124.0,13.0],[121.0,13.0]]]]}},
    {"type":"Feature","properties":{"NAME":"France","ADMIN":"France","ISO_A3":"FRA"},"geometry":{"type":"MultiPolygon","coordinates":[[[[-5.0,42.3],[-5.0,51.1],[8.2,51.1],[8.2,42.3],[-5.0,42.3]]],[[[8.5,41.3],[8.5,43.0],[9.6,43.0],[9.6,41.3],[8.5,41.3]]]]}},
    {"type":"Feature","properties":{"NAME":"Germany","ADMIN":"Germany","ISO_A3":"DEU"},"geometry":{"type":"Polygon","coordinates":[[[5.9,47.3],[5.9,55.0],[15.0,55.0],[15.0,47.3],[5.9,47.3]]]}}
  ]
}
FALLBACKEOF
        # Convert to Shapefile if ogr2ogr is available, otherwise leave as GeoJSON
        if command -v ogr2ogr &>/dev/null; then
            ogr2ogr -f "ESRI Shapefile" "$NE_DIR/ne_110m_admin_0_countries.shp" "$NE_DIR/ne_110m_admin_0_countries.geojson"
        else
            # Rename for the task description to match (agent sees .geojson but instruction says .shp is okay if not found)
            mv "$NE_DIR/ne_110m_admin_0_countries.geojson" "$NE_DIR/ne_110m_admin_0_countries.shp.geojson"
        fi
    fi
    rm -f "$NE_ZIP"
fi

chown -R ga:ga "$NE_DIR"
chown -R ga:ga /home/ga/GIS_Data

# Record initial feature count
INITIAL_COUNT=0
if [ -f "$NE_DIR/ne_110m_admin_0_countries.shp" ] && command -v ogrinfo &>/dev/null; then
    INITIAL_COUNT=$(ogrinfo -so "$NE_DIR/ne_110m_admin_0_countries.shp" ne_110m_admin_0_countries | grep "Feature Count" | awk '{print $NF}')
elif [ -f "$NE_DIR/ne_110m_admin_0_countries.geojson" ]; then
    INITIAL_COUNT=$(grep -c "MultiPolygon" "$NE_DIR/ne_110m_admin_0_countries.geojson" || echo "5")
fi
echo "${INITIAL_COUNT:-0}" > /tmp/initial_feature_count.txt

# Launch QGIS
kill_qgis ga 2>/dev/null || true
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis --noversioncheck --skipbadlayers > /dev/null 2>&1 &"

# Wait for QGIS
wait_for_window "QGIS" 40
sleep 2

# Maximize
if is_qgis_running; then
    WID=$(get_qgis_window_id)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    fi
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="