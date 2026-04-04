#!/bin/bash
# Setup script for Epidemic SIR Calibration task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions if task_utils missing
if ! type kill_geogebra &>/dev/null; then
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up SIR Calibration Task ==="

# 1. Clean environment
kill_geogebra ga
sleep 1
mkdir -p /home/ga/Documents/GeoGebra/projects
mkdir -p /home/ga/Documents/GeoGebra/data
chown -R ga:ga /home/ga/Documents/GeoGebra

# 2. Prepare the Data File (Real 1978 Boarding School Flu Data)
# Source: British Medical Journal, March 4, 1978
cat > /home/ga/Documents/GeoGebra/data/flu_1978.csv << 'CSV_EOF'
Day,Infected
0,1
3,25
4,75
5,227
6,296
7,258
8,236
9,192
10,126
11,71
12,28
13,11
14,7
CSV_EOF
chown ga:ga /home/ga/Documents/GeoGebra/data/flu_1978.csv

# 3. Remove existing target file to prevent false positives
rm -f /home/ga/Documents/GeoGebra/projects/sir_analysis.ggb 2>/dev/null || true

# 4. Record baseline
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 5. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# Wait for load
if wait_for_window "GeoGebra" 45; then
    echo "GeoGebra started successfully"
    sleep 5
    
    # Setup window
    su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
    focus_geogebra
    sleep 1
    maximize_geogebra
    sleep 1
else
    echo "WARNING: GeoGebra window not detected"
fi

# 6. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Data file: ~/Documents/GeoGebra/data/flu_1978.csv"
echo "Instructions:"
echo "1. Load data from CSV"
echo "2. Build SIR model (S'=-bSI/N, I'=bSI/N-gI, R'=gI)"
echo "3. Use SolveODE to simulate"
echo "4. Adjust sliders beta/gamma to fit data"
echo "5. Save to ~/Documents/GeoGebra/projects/sir_analysis.ggb"