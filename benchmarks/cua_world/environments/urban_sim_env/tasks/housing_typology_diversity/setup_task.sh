#!/bin/bash
echo "=== Setting up housing_typology_diversity task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects/output
chown -R ga:ga /home/ga/urbansim_projects/notebooks

date +%s > /home/ga/.task_start_time

if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

activate_venv
python -c "
import pandas as pd
buildings = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
assert len(buildings) > 100, 'Not enough building records'
assert len(parcels) > 100, 'Not enough parcel records'
print('Data verification passed')
"

cat > /home/ga/urbansim_projects/notebooks/housing_diversity_index.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Housing Typology Diversity Analysis\n",
    "\n",
    "Compute Simpson's Diversity Index for residential building types.\n",
    "\n",
    "## Requirements:\n",
    "- Load buildings and parcels data from `../data/sanfran_public.h5`\n",
    "- Join tables and filter to residential buildings only\n",
    "- Compute Simpson's Diversity Index by zone\n",
    "- Exclude zones with fewer than 10 residential buildings\n",
    "- Save CSV to `../output/zone_housing_diversity.csv`\n",
    "- Save PNG to `../output/diversity_vs_density.png`\n",
    "- Save JSON summary to `../output/diversity_summary.json`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/housing_diversity_index.ipynb

if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/housing_diversity_index.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/housing_diversity_index.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="