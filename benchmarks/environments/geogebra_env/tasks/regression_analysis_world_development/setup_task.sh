#!/bin/bash
# Setup script for Regression Analysis World Development task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

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

echo "=== Setting up Regression Analysis World Development Task ==="

# Kill existing GeoGebra
kill_geogebra ga
sleep 1

# Create directories
mkdir -p /home/ga/Documents/GeoGebra/projects
mkdir -p /home/ga/Documents/GeoGebra/data
chown -R ga:ga /home/ga/Documents/GeoGebra 2>/dev/null || true

# Remove existing target file
rm -f /home/ga/Documents/GeoGebra/projects/world_regression.ggb 2>/dev/null || true

# Create the real-world dataset CSV
# Source: United Nations Development Programme, Human Development Report 2021-22
# Table 1: Human Development Index and its components
# URL: https://hdr.undp.org/content/human-development-report-2021-22
# Values: GNI per capita (PPP 2017 international $) and Life Expectancy at birth (years)
# These are exact values from the published UN HDR 2021-22 Statistical Annex Table 1
cat > /home/ga/Documents/GeoGebra/data/world_development.csv << 'CSV_DATA'
Country,GNI_Per_Capita_PPP_USD,Life_Expectancy_Years
Norway,66494,83.2
Switzerland,66933,83.8
United States,64765,76.1
Germany,54534,80.6
United Kingdom,45225,80.7
Japan,42274,84.3
South Korea,44501,83.0
Spain,38661,83.3
Turkey,27701,77.7
Brazil,13628,75.0
China,17504,78.2
Mexico,17628,70.2
India,6590,67.2
Nigeria,5026,52.7
Ethiopia,2206,66.6
CSV_DATA

chown ga:ga /home/ga/Documents/GeoGebra/data/world_development.csv
echo "Data file created at /home/ga/Documents/GeoGebra/data/world_development.csv"
echo "Source: UN Human Development Report 2021-22, Table 1"

# Record baseline
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count

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

su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

if [ "${RANDOMIZE_VIEWPORT:-1}" != "0" ]; then
    randomize_geogebra_viewport ga :1
    sleep 0.5
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Regression Analysis Task Setup Complete ==="
echo ""
echo "TASK: Perform statistical regression analysis in GeoGebra."
echo "  - Data file: ~/Documents/GeoGebra/data/world_development.csv"
echo "  - Source: UN Human Development Report 2021-22"
echo "  - Enter all 15 data points (GNI per capita vs life expectancy)"
echo "  - Create scatter plot and fit linear regression (FitLine)"
echo "  - Also fit logarithmic regression (FitLog) for comparison"
echo "  - Add text annotations with regression equations"
echo "  - Save as: ~/Documents/GeoGebra/projects/world_regression.ggb"
