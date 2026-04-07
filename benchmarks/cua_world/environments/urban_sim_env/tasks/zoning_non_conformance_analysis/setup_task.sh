#!/bin/bash
echo "=== Setting up zoning_non_conformance_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Record task start time for anti-gaming verification
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

activate_venv
python -c "
import pandas as pd
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
pcl = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
zng = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'zoning')
print(f'Buildings: {len(bld)} rows')
print(f'Parcels: {len(pcl)} rows')
print(f'Zoning: {len(zng)} rows')
assert len(bld) > 100, 'Not enough building records'
assert len(pcl) > 100, 'Not enough parcel records'
print('Data verification passed')
"

# Create boilerplate notebook
cat > /home/ga/urbansim_projects/notebooks/zoning_non_conformance.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Zoning Non-Conformance Analysis\n",
    "\n",
    "Analyze San Francisco parcels to identify 'grandfathered' structures that exceed current zoning limits.\n",
    "\n",
    "## Requirements:\n",
    "- Load `buildings`, `parcels`, and `zoning` from `../data/sanfran_public.h5`\n",
    "- Calculate `total_building_sqft` per parcel\n",
    "- Calculate `parcel_sqft` = `parcel_acres` * 43560\n",
    "- Calculate `built_far` = `total_building_sqft` / `parcel_sqft`\n",
    "- Identify valid parcels (`max_far` > 0)\n",
    "- Identify non-conforming parcels (`built_far` > `max_far`)\n",
    "- Calculate `excess_sqft` = `total_building_sqft` - (`max_far` * `parcel_sqft`)\n",
    "- Save non-conforming parcels to `../output/non_conforming_parcels.csv` (sorted by excess_sqft descending)\n",
    "- Save zone summary counts to `../output/zone_non_conformance_counts.csv`\n",
    "- Save scatter plot to `../output/far_compliance_scatter.png` (include y=x line)"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/zoning_non_conformance.ipynb

# Record initial state
echo '{"notebook_exists": true, "csv1_exists": false, "csv2_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/zoning_non_conformance.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/zoning_non_conformance.ipynb"
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