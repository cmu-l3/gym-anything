#!/bin/bash
# Setup script for Pleiades HR Diagram Analysis
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions if task_utils.sh is missing
if ! type kill_geogebra &>/dev/null; then
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up Pleiades HR Diagram Task ==="

# 1. Kill existing instances
kill_geogebra ga

# 2. Prepare Directories
mkdir -p /home/ga/Documents/GeoGebra/data
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# 3. Create the Data File
# Real data from Hipparcos/SIMBAD for Pleiades (M45)
cat > /home/ga/Documents/GeoGebra/data/pleiades_raw_data.csv << 'EOF'
Star,B_V_Color,Apparent_Mag_m
Alcyone,-0.09,2.86
Atlas,-0.06,3.62
Electra,-0.06,3.70
Maia,-0.07,3.87
Merope,-0.06,4.17
Taygeta,-0.12,4.29
Pleione,-0.11,5.09
Celaeno,-0.04,5.44
Asterope,-0.05,5.64
HD 23753,0.03,5.44
HD 23246,0.21,5.60
HD 23923,0.40,6.17
HD 23352,0.45,6.18
HD 23410,0.52,6.48
HD 23629,0.58,6.80
HD 23480,0.65,7.20
HD 23964,0.72,7.50
HD 23408,0.85,8.10
EOF
chown ga:ga /home/ga/Documents/GeoGebra/data/pleiades_raw_data.csv
echo "Created data file at /home/ga/Documents/GeoGebra/data/pleiades_raw_data.csv"

# 4. Remove previous results
rm -f /home/ga/Documents/GeoGebra/projects/pleiades_analysis.ggb

# 5. Record Baseline
date +%s > /tmp/task_start_time

# 6. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga
sleep 5
wait_for_window "GeoGebra" 60

# 7. Set Window State
focus_geogebra
sleep 1
maximize_geogebra
sleep 1

# 8. Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="