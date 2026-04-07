#!/bin/bash
echo "=== Setting up noah_inventory_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects/

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi
if [ ! -f /home/ga/urbansim_projects/data/zones.json ]; then
    echo "ERROR: Zones GeoJSON not found at /home/ga/urbansim_projects/data/zones.json"
    exit 1
fi

activate_venv
python -c "
import pandas as pd
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Buildings: {len(bld)} rows')
print(f'Parcels: {len(parcels)} rows')
assert len(bld) > 100, 'Not enough building records'
assert len(parcels) > 100, 'Not enough parcel records'
print('Data verification passed')
"

# Create starting notebook for the agent
cat > /home/ga/urbansim_projects/notebooks/noah_inventory.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Naturally Occurring Affordable Housing (NOAH) Inventory\n",
    "\n",
    "Identify vulnerable multi-family buildings and map their concentration by zone.\n",
    "\n",
    "## Requirements:\n",
    "- Load `buildings` and `parcels` from `../data/sanfran_public.h5`\n",
    "- Filter buildings: Drop nulls, keep >= 4 units and built < 1990\n",
    "- Identify NOAH: `residential_sales_price` <= 33rd percentile of the filtered baseline\n",
    "- Join NOAH buildings to `parcels` to get `zone_id`\n",
    "- Save NOAH list to `../output/noah_buildings.csv`\n",
    "- Create a zone-level summary: count, NOAH units, total zone units, and `% NOAH`\n",
    "- Save summary to `../output/zone_noah_summary.csv`\n",
    "- Load `../data/zones.json` using GeoPandas, merge with summary\n",
    "- Save a choropleth map of `% NOAH` to `../output/noah_zones_map.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/noah_inventory.ipynb

# Record initial state
echo '{"notebook_exists": true, "csv1_exists": false, "csv2_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Start Jupyter Lab
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Start Firefox
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/noah_inventory.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/noah_inventory.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss dialogs and maximize
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Notebook: /home/ga/urbansim_projects/notebooks/noah_inventory.ipynb"