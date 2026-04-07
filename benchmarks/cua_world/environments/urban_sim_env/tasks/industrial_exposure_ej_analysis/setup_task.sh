#!/bin/bash
echo "=== Setting up industrial_exposure_ej_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create required directories
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects/output
chown -R ga:ga /home/ga/urbansim_projects/notebooks

# Record start time for anti-gaming verification
date +%s > /home/ga/.task_start_time

# Verify HDF5 dataset exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

# Quick test of data via python
activate_venv
python -c "
import pandas as pd
hh = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'households')
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
pcl = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Households: {len(hh)} rows')
print(f'Buildings: {len(bld)} rows')
print(f'Parcels: {len(pcl)} rows')
assert len(hh) > 100, 'Not enough household records'
print('Data verification passed')
"

# Create a starter notebook
cat > /home/ga/urbansim_projects/notebooks/industrial_exposure_ej.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Environmental Justice: Industrial Exposure Analysis\n",
    "\n",
    "Analyze the correlation between industrial exposure and median household income across San Francisco zones.\n",
    "\n",
    "## Requirements:\n",
    "- Load `households`, `buildings`, and `parcels` from `../data/sanfran_public.h5`\n",
    "- Link households and buildings to zones\n",
    "- Aggregate metrics by zone (sum industrial sqft where `building_type_id == 3`)\n",
    "- Filter out zones with fewer than 50 households\n",
    "- Rank zones into 4 quartiles based on `industrial_sqft_per_hh`\n",
    "- Save CSV to `../output/zone_industrial_exposure.csv`\n",
    "- Save JSON summary to `../output/ej_summary.json`\n",
    "- Save visualization to `../output/income_vs_exposure.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/industrial_exposure_ej.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Ensure Firefox is open to the correct notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/industrial_exposure_ej.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/industrial_exposure_ej.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="