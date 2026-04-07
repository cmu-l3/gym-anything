#!/bin/bash
echo "=== Setting up adu_capacity_analysis task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

date +%s > /home/ga/.task_start_time

if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

activate_venv
python -c "
import pandas as pd
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
print(f'Parcels: {len(parcels)} rows, columns: {list(parcels.columns)}')
print(f'Buildings: {len(bld)} rows, columns: {list(bld.columns)}')
assert len(parcels) > 100
assert len(bld) > 100
print('Data verification passed')
"

cat > /home/ga/urbansim_projects/notebooks/adu_capacity.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# ADU Capacity Analysis\n",
    "\n",
    "Estimate the physical capacity for Accessory Dwelling Units (ADUs) in San Francisco.\n",
    "\n",
    "## Requirements:\n",
    "- Load `buildings` and `parcels` tables from `../data/sanfran_public.h5`\n",
    "- Aggregate `residential_units` and `non_residential_sqft` by parcel\n",
    "- Identify ADU-eligible parcels (1 res unit, 0 non-res space, >= 3000 sqft parcel area)\n",
    "- Aggregate capacity by `zone_id`\n",
    "- Save CSV to `../output/zone_adu_capacity.csv`\n",
    "- Save summary JSON to `../output/adu_summary.json`\n",
    "- Save bar chart of top 15 zones to `../output/top_adu_zones.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/adu_capacity.ipynb

if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/adu_capacity.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/adu_capacity.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="