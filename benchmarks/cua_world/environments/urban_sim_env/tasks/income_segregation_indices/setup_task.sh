#!/bin/bash
echo "=== Setting up income_segregation_indices task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Clean up any pre-existing files
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
rm -f /home/ga/urbansim_projects/output/zone_income_distribution.csv
rm -f /home/ga/urbansim_projects/output/segregation_indices.json
rm -f /home/ga/urbansim_projects/output/income_segregation_chart.png
rm -f /home/ga/urbansim_projects/notebooks/income_segregation.ipynb

chown -R ga:ga /home/ga/urbansim_projects/

# Verify data file is accessible
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: Data file not found, copying from install location..."
    cp /opt/urbansim_data/sanfran_public.h5 /home/ga/urbansim_projects/data/
fi

# Ensure Jupyter Lab is running
if ! curl -s http://localhost:8888/api > /dev/null 2>&1; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && DISPLAY=:1 jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
fi

# Wait for Jupyter Lab
wait_for_jupyter 60

# Ensure Firefox is running and pointed to Jupyter
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize Firefox
FIREFOX_WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|Mozilla\|jupyter" | head -1 | awk '{print $1}')
if [ -n "$FIREFOX_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$FIREFOX_WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -i -a "$FIREFOX_WID"
fi

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="