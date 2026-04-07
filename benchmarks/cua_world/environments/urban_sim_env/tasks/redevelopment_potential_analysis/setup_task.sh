#!/bin/bash
echo "=== Setting up redevelopment_potential_analysis task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Timestamp for anti-gaming
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

activate_venv
python -c "
import pandas as pd
h5_path = '/home/ga/urbansim_projects/data/sanfran_public.h5'
buildings = pd.read_hdf(h5_path, 'buildings')
parcels = pd.read_hdf(h5_path, 'parcels')
zoning = pd.read_hdf(h5_path, 'zoning')
print(f'Buildings: {len(buildings)} rows')
print(f'Parcels: {len(parcels)} rows')
print(f'Zoning: {len(zoning)} rows')
assert len(buildings) > 100, 'Not enough buildings records'
print('Data verification passed')
"

cat > /home/ga/urbansim_projects/notebooks/redevelopment_potential.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Parcel Redevelopment Potential Analysis\n",
    "\n",
    "Compute a composite Redevelopment Potential Index (RPI) for San Francisco parcels.\n",
    "\n",
    "## Requirements:\n",
    "- Load `buildings`, `parcels`, `zoning` from `../data/sanfran_public.h5`\n",
    "- Compute `underutilization_score` = 1 - (actual_far / max_far) \n",
    "- Compute `age_score` (min-max normalized year_built, older = higher)\n",
    "- Compute `value_score` (min-max normalized value intensity, lower value = higher score)\n",
    "- Calculate `rpi` = 0.4 * underutilization_score + 0.35 * age_score + 0.25 * value_score\n",
    "- Save top 50 parcels by RPI to `../output/top_redevelopment_parcels.csv`\n",
    "- Save scatter plot to `../output/rpi_scatter.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/redevelopment_potential.ipynb

echo '{"notebook_exists": true, "csv_exists": false, "plot_exists": false}' > /tmp/initial_state.json

if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/redevelopment_potential.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/redevelopment_potential.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="