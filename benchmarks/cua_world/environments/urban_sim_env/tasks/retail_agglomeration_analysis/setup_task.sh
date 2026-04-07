#!/bin/bash
echo "=== Setting up retail_agglomeration_analysis task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

activate_venv
python -c "
import pandas as pd
jobs = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'jobs')
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Jobs: {len(jobs)} rows')
print(f'Buildings: {len(bld)} rows')
print(f'Parcels: {len(parcels)} rows')
assert len(jobs) > 100, 'Not enough job records'
print('Data verification passed')
"

cat > /home/ga/urbansim_projects/notebooks/retail_agglomeration.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Retail Agglomeration and Location Quotient Analysis\n",
    "\n",
    "Identify 'organic' retail clusters using UrbanSim micro-data.\n",
    "\n",
    "## Requirements:\n",
    "- Load `jobs`, `buildings`, and `parcels` from `../data/sanfran_public.h5`\n",
    "- Join tables to assign `zone_id` to every job\n",
    "- Calculate `total_jobs` and `retail_jobs` per zone (Retail = sector_id 10 or 11)\n",
    "- Calculate Location Quotient (LQ) for each zone\n",
    "- Identify 'Retail Centers' (LQ > 1.25 AND retail_jobs >= 100)\n",
    "- Save full analysis to `../output/zone_lq_analysis.csv`\n",
    "- Save filtered Retail Centers to `../output/retail_centers.csv`\n",
    "- Save a scatter plot (Total Jobs vs Retail LQ) to `../output/retail_lq_plot.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/retail_agglomeration.ipynb

if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/retail_agglomeration.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/retail_agglomeration.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="