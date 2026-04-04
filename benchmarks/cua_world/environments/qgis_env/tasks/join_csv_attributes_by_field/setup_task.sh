#!/bin/bash
echo "=== Setting up join_csv_attributes_by_field task ==="

source /workspace/scripts/task_utils.sh

# Directory setup
DATA_DIR="/home/ga/GIS_Data"
mkdir -p "$DATA_DIR"
mkdir -p "$DATA_DIR/exports"

# Clean previous outputs
rm -f "$DATA_DIR/exports/countries_with_statistics.geojson" 2>/dev/null
rm -f "$DATA_DIR/ne_countries_geometry.geojson" 2>/dev/null
rm -f "$DATA_DIR/country_statistics.csv" 2>/dev/null

# ------------------------------------------------------------------
# PREPARE REAL DATA
# We download the Natural Earth 110m countries dataset and split it
# into geometry-only and attributes-only files to simulate the task.
# ------------------------------------------------------------------

echo "Preparing dataset..."

# Use Python to download and process data using geopandas
# This ensures we have valid, real-world data structure
python3 << 'PYEOF'
import geopandas as gpd
import pandas as pd
import os
import urllib.request
import zipfile
import shutil

data_dir = "/home/ga/GIS_Data"
ne_url = "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip"
zip_path = os.path.join(data_dir, "ne_countries.zip")
extract_dir = os.path.join(data_dir, "ne_temp")

try:
    # 1. Download
    print(f"Downloading {ne_url}...")
    # standard user agent to avoid blocking
    opener = urllib.request.build_opener()
    opener.addheaders = [('User-agent', 'Mozilla/5.0')]
    urllib.request.install_opener(opener)
    urllib.request.urlretrieve(ne_url, zip_path)

    # 2. Extract
    os.makedirs(extract_dir, exist_ok=True)
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall(extract_dir)

    # 3. Load Shapefile
    shp_file = [f for f in os.listdir(extract_dir) if f.endswith('.shp')][0]
    gdf = gpd.read_file(os.path.join(extract_dir, shp_file))

    # 4. Prepare Geometry Layer (Keep minimal attributes)
    # We keep ISO_A3 as the join key, and NAME for reference
    cols_geom = ['NAME', 'ISO_A3', 'CONTINENT', 'geometry']
    # Ensure ISO_A3 is valid (not -99) for the task to work well
    gdf_clean = gdf[gdf['ISO_A3'] != '-99'].copy()
    
    # Save Geometry GeoJSON
    geom_out = os.path.join(data_dir, "ne_countries_geometry.geojson")
    gdf_clean[cols_geom].to_file(geom_out, driver='GeoJSON')
    print(f"Created {geom_out}")

    # 5. Prepare Statistics CSV (Drop geometry, keep stats)
    # Fields: ISO_A3 (Key), POP_EST, GDP_MD, ECONOMY, INCOME_GRP, SUBREGION
    cols_stats = ['ISO_A3', 'POP_EST', 'GDP_MD', 'ECONOMY', 'INCOME_GRP', 'SUBREGION']
    stats_out = os.path.join(data_dir, "country_statistics.csv")
    
    # Convert to DataFrame and drop geometry
    df = pd.DataFrame(gdf_clean)
    df[cols_stats].to_csv(stats_out, index=False)
    print(f"Created {stats_out}")

    # Cleanup
    shutil.rmtree(extract_dir)
    os.remove(zip_path)

except Exception as e:
    print(f"Error preparing data: {e}")
    exit(1)
PYEOF

# Ensure ownership
chown -R ga:ga "$DATA_DIR"

# Check if data preparation succeeded
if [ ! -f "$DATA_DIR/ne_countries_geometry.geojson" ] || [ ! -f "$DATA_DIR/country_statistics.csv" ]; then
    echo "ERROR: Data preparation failed."
    exit 1
fi

# ------------------------------------------------------------------
# APP SETUP
# ------------------------------------------------------------------

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure QGIS is running
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for window
wait_for_window "QGIS" 60
sleep 5

# Maximize
wid=$(get_qgis_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="