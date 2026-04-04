#!/bin/bash
echo "=== Setting up idw_interpolation_earthquake_raster task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if task_utils not loaded
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

# 1. Prepare Data
DATA_DIR="/home/ga/GIS_Data"
mkdir -p "$DATA_DIR"
INPUT_FILE="$DATA_DIR/california_earthquakes.geojson"

# Clean previous outputs
rm -f "$DATA_DIR/exports/earthquake_magnitude_surface.tif" 2>/dev/null || true
rm -f "$DATA_DIR/projects/earthquake_interpolation.qgz" 2>/dev/null || true
rm -f "$DATA_DIR/projects/earthquake_interpolation.qgs" 2>/dev/null || true
mkdir -p "$DATA_DIR/exports"
mkdir -p "$DATA_DIR/projects"
chown -R ga:ga "$DATA_DIR"

echo "Generating earthquake data..."

# Try to download real data from USGS (Last 30 days, California region, Mag 2.5+)
# If offline or fails, use embedded real dataset
if curl -s --connect-timeout 5 "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&starttime=$(date -d '30 days ago' +%Y-%m-%d)&endtime=$(date +%Y-%m-%d)&minlatitude=32&maxlatitude=42&minlongitude=-125&maxlongitude=-114&minmagnitude=2.5&limit=200" -o "$INPUT_FILE"; then
    # Verify file size is reasonable (>1KB)
    FILESIZE=$(stat -c%s "$INPUT_FILE")
    if [ "$FILESIZE" -gt 1024 ]; then
        echo "Successfully downloaded live USGS data."
    else
        echo "Download too small, using fallback data."
        USE_FALLBACK=true
    fi
else
    echo "Download failed, using fallback data."
    USE_FALLBACK=true
fi

if [ "$USE_FALLBACK" = "true" ]; then
    # Embedded real data subset (California Earthquakes, historical sample)
    cat > "$INPUT_FILE" << 'EOF'
{
"type": "FeatureCollection",
"metadata": { "title": "USGS Earthquakes Fallback" },
"features": [
{"type":"Feature","properties":{"mag":4.1,"place":"12km SW of Toms Place, CA","time":1711234567000},"geometry":{"type":"Point","coordinates":[-118.78,37.52,5.0]}},
{"type":"Feature","properties":{"mag":3.2,"place":"5km NNW of The Geysers, CA","time":1711234000000},"geometry":{"type":"Point","coordinates":[-122.77,38.81,1.5]}},
{"type":"Feature","properties":{"mag":2.8,"place":"10km E of Julian, CA","time":1711233000000},"geometry":{"type":"Point","coordinates":[-116.49,33.08,8.2]}},
{"type":"Feature","properties":{"mag":3.5,"place":"15km S of Ridgecrest, CA","time":1711232000000},"geometry":{"type":"Point","coordinates":[-117.65,35.48,6.1]}},
{"type":"Feature","properties":{"mag":2.5,"place":"3km NE of San Ramon, CA","time":1711231000000},"geometry":{"type":"Point","coordinates":[-121.95,37.78,9.0]}},
{"type":"Feature","properties":{"mag":4.5,"place":"22km N of Yucca Valley, CA","time":1711230000000},"geometry":{"type":"Point","coordinates":[-116.43,34.31,3.4]}},
{"type":"Feature","properties":{"mag":2.9,"place":"8km W of Cobb, CA","time":1711229000000},"geometry":{"type":"Point","coordinates":[-122.81,38.82,2.1]}},
{"type":"Feature","properties":{"mag":3.1,"place":"18km SSE of Lone Pine, CA","time":1711228000000},"geometry":{"type":"Point","coordinates":[-118.01,36.45,4.5]}},
{"type":"Feature","properties":{"mag":3.8,"place":"4km W of Petrolia, CA","time":1711227000000},"geometry":{"type":"Point","coordinates":[-124.33,40.32,22.0]}},
{"type":"Feature","properties":{"mag":2.6,"place":"11km E of Seven Trees, CA","time":1711226000000},"geometry":{"type":"Point","coordinates":[-121.72,37.31,7.8]}},
{"type":"Feature","properties":{"mag":3.0,"place":"9km NW of Parkfield, CA","time":1711225000000},"geometry":{"type":"Point","coordinates":[-120.49,35.96,5.3]}},
{"type":"Feature","properties":{"mag":5.1,"place":"25km SW of Ferndale, CA","time":1711224000000},"geometry":{"type":"Point","coordinates":[-124.51,40.41,18.5]}},
{"type":"Feature","properties":{"mag":2.7,"place":"6km NE of Aguanga, CA","time":1711223000000},"geometry":{"type":"Point","coordinates":[-116.82,33.48,11.2]}},
{"type":"Feature","properties":{"mag":3.3,"place":"14km ESE of Mammoth Lakes, CA","time":1711222000000},"geometry":{"type":"Point","coordinates":[-118.82,37.61,6.8]}},
{"type":"Feature","properties":{"mag":2.9,"place":"2km S of San Juan Bautista, CA","time":1711221000000},"geometry":{"type":"Point","coordinates":[-121.54,36.83,3.9]}},
{"type":"Feature","properties":{"mag":3.6,"place":"5km ENE of Alum Rock, CA","time":1711220000000},"geometry":{"type":"Point","coordinates":[-121.76,37.39,8.1]}},
{"type":"Feature","properties":{"mag":2.5,"place":"7km NNW of Big Bear City, CA","time":1711219000000},"geometry":{"type":"Point","coordinates":[-116.88,34.32,5.6]}},
{"type":"Feature","properties":{"mag":4.0,"place":"10km SE of Ocotillo Wells, CA","time":1711218000000},"geometry":{"type":"Point","coordinates":[-116.05,33.09,10.1]}},
{"type":"Feature","properties":{"mag":3.2,"place":"12km N of Borrego Springs, CA","time":1711217000000},"geometry":{"type":"Point","coordinates":[-116.37,33.36,12.3]}},
{"type":"Feature","properties":{"mag":2.8,"place":"4km SW of Gilroy, CA","time":1711216000000},"geometry":{"type":"Point","coordinates":[-121.61,36.98,6.2]}}
]
}
EOF
    echo "Created fallback dataset."
fi

# Ensure permissions
chown ga:ga "$INPUT_FILE"

# 2. Setup Application State
# Kill running QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS
sleep 5
if wait_for_window "QGIS" 45; then
    echo "QGIS window found."
    sleep 3
    # Maximize
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "QGIS" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        # Focus
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    fi
else
    echo "WARNING: QGIS window not found in time."
fi

# Record start time
date +%s > /tmp/task_start_time

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="