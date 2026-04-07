#!/bin/bash
# Setup script for Tensile Test Ramberg-Osgood Yield Strength task
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions if task_utils.sh unavailable
if ! type kill_geogebra &>/dev/null; then
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up Tensile Test Ramberg-Osgood Yield Task ==="

# 1. Kill existing GeoGebra instances
kill_geogebra ga
sleep 1

# 2. Prepare directories
mkdir -p /home/ga/Documents/GeoGebra/projects
mkdir -p /home/ga/Documents/GeoGebra/data
chown -R ga:ga /home/ga/Documents/GeoGebra

# 3. Remove any previous attempt file (BEFORE recording timestamp)
rm -f /home/ga/Documents/GeoGebra/projects/tensile_analysis.ggb 2>/dev/null || true

# 4. Record baseline state for anti-gaming verification
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 5. Write the tensile test data file
# Source: 6061-T6 aluminum alloy tensile test data
# Ramberg-Osgood model (E=69 GPa, K=450 MPa, n=10) with measurement noise
# Data follows ASTM E8 tensile testing protocol
cat > /home/ga/Documents/GeoGebra/data/tensile_test.csv << 'CSV_EOF'
Tensile Test Results - 6061-T6 Aluminum Alloy
Test standard: ASTM E8/E8M
Specimen: Flat dog-bone, gauge length 50 mm
Strain rate: 0.001 /s
Temperature: 23 C

Material reference:
  Elastic Modulus: E = 69 GPa

Stress_MPa,Strain_Percent
0,0.000
50,0.072
100,0.144
150,0.219
200,0.324
225,0.423
250,0.623
260,0.797
275,1.119
300,2.160
325,4.342
350,8.649
CSV_EOF
chown ga:ga /home/ga/Documents/GeoGebra/data/tensile_test.csv

# 6. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# 7. Wait for application to be ready
if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window not detected within timeout"
fi

sleep 5

# 8. Focus and maximize
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# 9. Dismiss any startup dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 0.5

# 10. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Data file: ~/Documents/GeoGebra/data/tensile_test.csv"
