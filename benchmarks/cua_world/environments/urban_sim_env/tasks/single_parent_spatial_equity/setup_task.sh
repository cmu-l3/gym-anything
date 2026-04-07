#!/bin/bash
echo "=== Setting up single_parent_spatial_equity task ==="

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
store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
hh = store['households']
jobs = store['jobs']
bld = store['buildings']
parcels = store['parcels']
store.close()
print(f'Data verification passed. HH: {len(hh)}, Jobs: {len(jobs)}, Bld: {len(bld)}, Parcels: {len(parcels)}')
"

cat > /home/ga/urbansim_projects/notebooks/single_parent_equity.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Single-Parent Household Spatial Equity Analysis\n",
    "\n",
    "Analyze the spatial distribution of single-parent households and their accessibility to jobs vs neighborhood income.\n",
    "\n",
    "## Requirements:\n",
    "- Load households, jobs, buildings, and parcels from `../data/sanfran_public.h5`\n",
    "- Filter invalid records and identify single-parent households (1 adult, >0 children)\n",
    "- Perform spatial joins to assign zone_ids\n",
    "- Aggregate metrics by zone_id and filter valid zones (>=50 households, >0 acres)\n",
    "- Calculate correlations\n",
    "- Export CSV to `../output/zone_single_parent_metrics.csv`\n",
    "- Export JSON to `../output/equity_summary.json`\n",
    "- Export bubble chart to `../output/single_parent_bubble_chart.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/single_parent_equity.ipynb

if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/single_parent_equity.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/single_parent_equity.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="