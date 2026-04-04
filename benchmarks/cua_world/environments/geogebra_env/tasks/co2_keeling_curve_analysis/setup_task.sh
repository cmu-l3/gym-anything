#!/bin/bash
set -o pipefail

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallbacks if utils missing
if ! type launch_geogebra &>/dev/null; then
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra.log 2>&1 &"; }
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up CO2 Analysis Task ==="

# 1. Cleanup previous run
kill_geogebra ga
sleep 1
rm -f /home/ga/Documents/GeoGebra/projects/co2_analysis.ggb 2>/dev/null || true

# 2. Prepare Data Directory
DATA_DIR="/home/ga/Documents/GeoGebra/data"
mkdir -p "$DATA_DIR"
chown -R ga:ga "/home/ga/Documents/GeoGebra"

# 3. Download Real Data
# Using NOAA Mauna Loa Monthly Mean CO2
echo "Downloading CO2 data..."
# Use a known stable snapshot if external network is flaky, but here we try live or fallback
# Since we need real data, we download it.
URL="https://gml.noaa.gov/webdata/ccgg/trends/co2/co2_mm_mlo.csv"
if curl -L -o "$DATA_DIR/co2_mlo_monthly.csv" "$URL"; then
    echo "Download successful."
else
    echo "Download failed, creating fallback data (Real subset)..."
    # Create a small valid subset if download fails to prevent task breakage
    cat > "$DATA_DIR/co2_mlo_monthly.csv" << EOF
# Mauna Loa CO2 monthly mean data
# year,month,decimal date,average,interpolated,trend,ndays
2020,1,2020.042,413.37,413.37,412.39,29
2020,2,2020.125,414.28,414.28,412.92,28
2020,3,2020.208,414.61,414.61,413.23,28
2020,4,2020.292,416.36,416.36,413.62,29
2020,5,2020.375,417.31,417.31,413.91,28
2020,6,2020.458,416.54,416.54,414.22,29
EOF
fi
chown ga:ga "$DATA_DIR/co2_mlo_monthly.csv"

# 4. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# 5. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "GeoGebra"; then
        echo "GeoGebra window found."
        break
    fi
    sleep 1
done
sleep 5

# 6. Configure UI
# Maximize window
DISPLAY=:1 wmctrl -r "GeoGebra" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Focus window
DISPLAY=:1 wmctrl -a "GeoGebra" 2>/dev/null || true
# Click center to dismiss any welcome tooltips
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="