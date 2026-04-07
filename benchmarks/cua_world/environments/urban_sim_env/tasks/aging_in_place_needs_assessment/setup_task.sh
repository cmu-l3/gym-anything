#!/bin/bash
echo "=== Setting up aging_in_place_needs_assessment task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

activate_venv
python -c "
import pandas as pd
hh = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'households')
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Households table: {len(hh)} rows, columns: {list(hh.columns)}')
print(f'Buildings table: {len(bld)} rows, columns: {list(bld.columns)}')
print(f'Parcels table: {len(parcels)} rows, columns: {list(parcels.columns)}')
assert len(hh) > 1000, 'Not enough household records'
print('Data verification passed')
"

cat > /home/ga/urbansim_projects/notebooks/aging_in_place.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Aging in Place Needs Assessment\n",
    "\n",
    "Identify zones with high concentrations of vulnerable senior households.\n",
    "\n",
    "## Requirements:\n",
    "- Load households, buildings, and parcels from `../data/sanfran_public.h5`\n",
    "- Filter for senior households (age_of_head >= 65)\n",
    "- Calculate zone-level vulnerability metrics\n",
    "- Save top 20 vulnerable zones to `../output/senior_vulnerability_top20.csv`\n",
    "- Save city summary to `../output/senior_summary.json`\n",
    "- Save scatter plot to `../output/vulnerability_scatter.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/aging_in_place.ipynb

echo '{"notebook_exists": true}' > /tmp/initial_state.json

if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/aging_in_place.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/aging_in_place.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="