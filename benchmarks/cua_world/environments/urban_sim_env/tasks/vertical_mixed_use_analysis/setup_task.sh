#!/bin/bash
echo "=== Setting up vertical_mixed_use_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown ga:ga -R /home/ga/urbansim_projects

# Record task start time for anti-gaming verification
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists and is accessible
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

activate_venv
python -c "
import pandas as pd
store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
required_tables = ['buildings', 'parcels', 'households', 'jobs']
for table in required_tables:
    assert table in store, f'{table} missing from HDF5 datastore'
store.close()
print('Data verification passed')
"

# Create skeleton notebook
cat > /home/ga/urbansim_projects/notebooks/mixed_use_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Vertical Mixed-Use Analysis\n",
    "\n",
    "Identify buildings that contain both households and jobs, and aggregate this data to the zone level.\n",
    "\n",
    "## Output Requirements:\n",
    "- Zone-level dataset containing zones with >= 10 buildings exported to `../output/vmu_by_zone.csv`\n",
    "- Summary JSON exported to `../output/vmu_summary.json`\n",
    "- Scatter plot exported to `../output/vmu_scatter.png`\n"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/mixed_use_analysis.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox pointing directly to the new notebook
if ! is_firefox_running; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/mixed_use_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    echo "Navigating existing Firefox..."
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/mixed_use_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss UI overlays and maximize
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="