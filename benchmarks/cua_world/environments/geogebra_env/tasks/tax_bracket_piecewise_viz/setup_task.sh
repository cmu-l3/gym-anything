#!/bin/bash
# Setup script for Tax Bracket Visualization task

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

echo "=== Setting up Tax Bracket Visualization Task ==="

# Kill any existing GeoGebra processes
kill_geogebra ga
sleep 1

# Create directories
mkdir -p /home/ga/Documents/GeoGebra/projects
mkdir -p /home/ga/Documents/GeoGebra/data
chown -R ga:ga /home/ga/Documents/GeoGebra 2>/dev/null || true

# Clean up previous results
rm -f /home/ga/Documents/GeoGebra/projects/tax_brackets.ggb 2>/dev/null || true

# Create the reference data file
cat > /home/ga/Documents/GeoGebra/data/tax_brackets_2024.txt << 'EOF'
2024 US Federal Income Tax Brackets — Single Filer
Source: IRS Revenue Procedure 2023-34

Bracket  Income From    Income To      Rate    Cumulative Tax at Start
1        $0             $11,600        10%     $0.00
2        $11,601        $47,150        12%     $1,160.00
3        $47,151        $100,525       22%     $5,426.00
4        $100,526       $191,950       24%     $17,168.50
5        $191,951       $243,725       32%     $39,110.50
6        $243,726       $609,350       35%     $55,678.50
7        $609,351+                     37%     $183,647.25

Formula Logic Example:
If Income = 50,000:
   Base Tax (Bracket 3 start) = 5,426.00
   Excess over 47,150 = 50,000 - 47,150 = 2,850
   Tax on excess = 2,850 * 0.22 = 627
   Total Tax = 5,426 + 627 = 6,053
EOF
chown ga:ga /home/ga/Documents/GeoGebra/data/tax_brackets_2024.txt

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

if ! wait_for_window "GeoGebra" 30; then
    echo "WARNING: GeoGebra window may not have appeared"
fi
sleep 2

# Click to ensure focus and dismiss any popups
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Tax Bracket Visualization Setup Complete ==="