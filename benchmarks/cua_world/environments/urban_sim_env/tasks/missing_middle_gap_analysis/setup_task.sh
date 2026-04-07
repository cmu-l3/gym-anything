#!/bin/bash
echo "=== Setting up missing_middle_gap_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Record task start time
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

# Verify data has buildings and parcels tables
activate_venv
python -c "
import pandas as pd
buildings = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Buildings table: {len(buildings)} rows, Parcels: {len(parcels)} rows')
assert len(buildings) > 100, 'Not enough building records'
assert len(parcels) > 100, 'Not enough parcel records'
print('Data verification passed')
"

# Create empty notebook for the task
cat > /home/ga/urbansim_projects/notebooks/missing_middle.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Missing Middle Housing Gap Analysis\n",
    "\n",
    "Identify SF zones with high single-family density but lacking missing middle housing.\n",
    "\n",
    "## Requirements:\n",
    "- Load `buildings` and `parcels` from `../data/sanfran_public.h5`\n",
    "- Calculate total *units* (not buildings) per category per zone:\n",
    "  - Single-Family: 1 unit\n",
    "  - Missing Middle: 2-19 units\n",
    "  - High-Density: 20+ units\n",
    "- Filter to zones with >= 100 total units\n",
    "- Flag Opportunity Zones (SF > 50% and MM < 15%)\n",
    "- Save CSV to `../output/missing_middle_zones.csv`\n",
    "- Save stacked bar chart to `../output/opportunity_zones_chart.png`"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Write your code here\n"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "UrbanSim (Python 3)",
   "language": "python",
   "name": "urbansim"
  },
  "language_info": {
   "name": "python",
   "version": "3.10.0"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
NOTEBOOK_EOF
chown ga:ga /home/ga/urbansim_projects/notebooks/missing_middle.ipynb

# Record initial state
echo '{"notebook_exists": true, "csv_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/missing_middle.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/missing_middle.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss dialogs and maximize
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot after browser is ready
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="