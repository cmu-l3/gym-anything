#!/bin/bash
echo "=== Setting up building_energy_baseline task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Record task start time
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF public data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

if [ ! -f /home/ga/urbansim_projects/data/zones.json ]; then
    echo "ERROR: Zones GeoJSON not found at /home/ga/urbansim_projects/data/zones.json"
    exit 1
fi

activate_venv
python -c "
import pandas as pd
buildings = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Buildings table: {len(buildings)} rows')
print(f'Parcels table: {len(parcels)} rows')
assert len(buildings) > 100, 'Not enough building records'
assert len(parcels) > 100, 'Not enough parcel records'
print('Data verification passed')
"

# Create starter notebook
cat > /home/ga/urbansim_projects/notebooks/energy_baseline.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Building Energy Consumption Baseline\n",
    "\n",
    "Calculate estimated baseline energy consumption for all buildings in San Francisco based on age and size.\n",
    "\n",
    "## Requirements:\n",
    "- Load buildings and parcels from `../data/sanfran_public.h5`\n",
    "- Assign a `zone_id` to each building using the parcels table\n",
    "- Calculate `total_sqft` (building_sqft or (residential_units * 800) + non_residential_sqft)\n",
    "- Filter out `total_sqft == 0`\n",
    "- Calculate EUI and `energy_kwh` based on year_built\n",
    "- Aggregate sum of `total_energy_kwh` and count of `total_buildings` by `zone_id`\n",
    "- Save summary CSV to `../output/zone_energy_baseline.csv`\n",
    "- Load `../data/zones.json` with geopandas\n",
    "- Merge aggregated data and create a choropleth map of `total_energy_kwh`\n",
    "- Save map to `../output/energy_map.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/energy_baseline.ipynb

# Record initial state
echo '{"notebook_exists": true, "csv_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/energy_baseline.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/energy_baseline.ipynb"
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