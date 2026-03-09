#!/bin/bash
# Setup script for Normal Empirical Rule Visualization task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions if task_utils.sh unavailable
if ! type kill_geogebra &>/dev/null; then
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_process() { local p=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do pgrep -f "$p" > /dev/null 2>&1 && return 0; sleep 1; e=$((e+1)); done; return 1; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
    randomize_geogebra_viewport() { true; }
fi

echo "=== Setting up Normal Empirical Rule Task ==="

# Kill existing GeoGebra processes
kill_geogebra ga
sleep 1

# Create directories
mkdir -p /home/ga/Documents/GeoGebra/projects
mkdir -p /home/ga/Documents/GeoGebra/data
chown -R ga:ga /home/ga/Documents/GeoGebra 2>/dev/null || true

# Remove any existing target file
rm -f /home/ga/Documents/GeoGebra/projects/normal_empirical_rule.ggb 2>/dev/null || true

# Create the data CSV file with parameters
# CDC NHANES 2015-2018 Data (Males 20+)
cat > /home/ga/Documents/GeoGebra/data/nhanes_height_params.csv << 'CSV_DATA'
Parameter,Value,Unit,Description
Mean Height,175.4,cm,Average adult male height
Standard Deviation,7.2,cm,Derived from 5th-95th percentile
-1 Sigma,168.2,cm,Mean - 1*SD
+1 Sigma,182.6,cm,Mean + 1*SD
-2 Sigma,161.0,cm,Mean - 2*SD
+2 Sigma,189.8,cm,Mean + 2*SD
-3 Sigma,153.8,cm,Mean - 3*SD
+3 Sigma,197.0,cm,Mean + 3*SD
CSV_DATA
chown ga:ga /home/ga/Documents/GeoGebra/data/nhanes_height_params.csv
echo "Data file created at /home/ga/Documents/GeoGebra/data/nhanes_height_params.csv"

# Record task start time
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

if ! wait_for_process "geogebra" 30; then
    echo "WARNING: GeoGebra may not have started"
fi
if ! wait_for_window "GeoGebra" 30; then
    echo "WARNING: GeoGebra window may not have appeared"
fi
sleep 2

# Focus and maximize
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# Randomize viewport
if [ "${RANDOMIZE_VIEWPORT:-1}" != "0" ]; then
    randomize_geogebra_viewport ga :1
    sleep 0.5
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Normal Empirical Rule Task Setup Complete ==="
echo ""
echo "TASK: Create a Normal Distribution visualization (Empirical Rule)."
echo "  - Parameters: Mean = 175.4, SD = 7.2"
echo "  - Create the Normal PDF curve"
echo "  - Shade regions for ±1σ, ±2σ, ±3σ"
echo "  - Add text labels for 68%, 95%, 99.7%"
echo "  - Save as: ~/Documents/GeoGebra/projects/normal_empirical_rule.ggb"