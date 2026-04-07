#!/bin/bash
echo "=== Setting up urban_water_demand_forecasting task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Record task start time (for anti-gaming detection)
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

# Initial state check
activate_venv
python -c "
import pandas as pd
h5_path = '/home/ga/urbansim_projects/data/sanfran_public.h5'
hh = pd.read_hdf(h5_path, 'households')
bld = pd.read_hdf(h5_path, 'buildings')
pcl = pd.read_hdf(h5_path, 'parcels')
print(f'Households: {len(hh)}, Buildings: {len(bld)}, Parcels: {len(pcl)}')
assert len(hh) > 1000, 'Insufficient household data'
print('Data verification passed')
"

# Create starting notebook for the agent
cat > /home/ga/urbansim_projects/notebooks/water_demand.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Urban Water Demand Forecasting\n",
    "\n",
    "Estimate daily water demand across San Francisco zones using population and commercial square footage.\n",
    "\n",
    "## Task Checklist:\n",
    "- [ ] Load `households`, `buildings`, and `parcels` tables from `../data/sanfran_public.h5`\n",
    "- [ ] Join tables to aggregate `total_persons` and `total_non_res_sqft` by `zone_id`\n",
    "- [ ] Calculate `residential_demand_gpd` (persons * 55.0)\n",
    "- [ ] Calculate `commercial_demand_gpd` (sqft * 0.15)\n",
    "- [ ] Calculate `total_demand_gpd` and `gross_per_capita_gpd`\n",
    "- [ ] Save required CSVs (full, top 15 total demand, top 15 per capita with >=100 persons)\n",
    "- [ ] Save `water_summary.json`\n",
    "- [ ] Save scatter plot `water_demand_scatter.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/water_demand.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/water_demand.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/water_demand.ipynb"
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