#!/bin/bash
set -e
echo "=== Setting up create_image_mosaic task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial state
INITIAL_LAYER_COUNT=$(get_layer_count)
echo "$INITIAL_LAYER_COUNT" > /tmp/initial_layer_count
echo "Initial layer count: $INITIAL_LAYER_COUNT"

# ============================================================
# Prepare Real Raster Data (4 Quadrants)
# ============================================================
echo "Generating quadrant raster tiles from Natural Earth vectors..."

# We need to generate 4 GeoTIFFs using GDAL. The gs-postgis container has GDAL installed.
# We will generate them there, then move them to the GeoServer data directory.

# 1. ensure shapefile is in gs-postgis
if ! docker exec gs-postgis test -f /tmp/ne_110m_admin_0_countries.shp; then
    echo "Copying shapefiles to postgis container..."
    for ext in shp shx dbf prj; do
        if [ -f "/home/ga/natural_earth/ne_110m_admin_0_countries.${ext}" ]; then
            docker cp "/home/ga/natural_earth/ne_110m_admin_0_countries.${ext}" gs-postgis:/tmp/
        fi
    done
fi

# 2. Define function to generate tile
generate_tile() {
    local name=$1
    local te=$2 # minx miny maxx maxy
    echo "Generating $name.tif ($te)..."
    
    # Rasterize: Burn 255 for land, init to 0 (water)
    # Output type Byte. LZW compression.
    docker exec gs-postgis gdal_rasterize \
        -a_srs EPSG:4326 \
        -burn 255 \
        -tr 1.0 1.0 \
        -te $te \
        -ot Byte \
        -init 0 \
        -co COMPRESS=LZW \
        -q \
        /tmp/ne_110m_admin_0_countries.shp \
        "/tmp/${name}.tif"
}

# 3. Generate 4 quadrants
# Global extent: -180 -90 180 90
generate_tile "nw" "-180 0 0 90"
generate_tile "ne" "0 0 180 90"
generate_tile "sw" "-180 -90 0 0"
generate_tile "se" "0 -90 180 0"

# 4. Prepare directory in GeoServer container
echo "Setting up GeoServer data directory..."
# GeoServer data dir is usually /opt/geoserver/data_dir
docker exec gs-app mkdir -p /opt/geoserver/data_dir/mosaics/world_quadrants

# 5. Move files: gs-postgis -> host -> gs-app
mkdir -p /tmp/mosaics
for tile in nw ne sw se; do
    # Copy from postgis to host
    docker cp "gs-postgis:/tmp/${tile}.tif" "/tmp/mosaics/${tile}.tif"
    # Copy from host to geoserver
    docker cp "/tmp/mosaics/${tile}.tif" "gs-app:/opt/geoserver/data_dir/mosaics/world_quadrants/${tile}.tif"
done

# 6. Fix permissions in GeoServer container
docker exec gs-app chown -R users:users /opt/geoserver/data_dir/mosaics
docker exec gs-app chmod -R 777 /opt/geoserver/data_dir/mosaics
# Also create a .properties file if needed? No, ImageMosaic plugin handles it.
# Ideally, we should ensure the plugin is loaded. Standard GeoServer includes it.

echo "Mosaic tiles prepared in gs-app:/opt/geoserver/data_dir/mosaics/world_quadrants"

# ============================================================
# Browser Setup
# ============================================================

# Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &
    sleep 5
fi
wait_for_window "firefox\|mozilla" 30
ensure_logged_in

# Focus Firefox
focus_firefox
DISPLAY=:1 xdotool mousemove 960 540 click 1
sleep 1

# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== create_image_mosaic task setup complete ==="