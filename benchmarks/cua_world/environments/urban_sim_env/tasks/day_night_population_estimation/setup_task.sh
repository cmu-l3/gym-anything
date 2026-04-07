#!/bin/bash
echo "=== Setting up day_night_population_estimation task ==="

source /workspace/scripts/task_utils.sh

# Create standard directories
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects/output
chown -R ga:ga /home/ga/urbansim_projects/notebooks

# Record task start time for anti-gaming verification
date +%s > /home/ga/.task_start_time

# Verify HDF5 dataset and JSON zones exist
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ] || [ ! -f /home/ga/urbansim_projects/data/zones.json ]; then
    echo "ERROR: SF UrbanSim data or zones.json not found."
    exit 1
fi

activate_venv
# Quick validation of the data
python -c "
import pandas as pd
import json
store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
required = ['households', 'jobs', 'buildings', 'parcels']
for req in required:
    assert req in store.keys() or f'/{req}' in store.keys(), f'Missing table {req}'
store.close()
print('Data verification passed.')
"

# Create a template notebook for the agent
cat > /home/ga/urbansim_projects/notebooks/day_night_population.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Day/Night Population Surge Analysis\n",
    "\n",
    "Estimate and map the shifting daytime versus nighttime populations across San Francisco zones.\n",
    "\n",
    "## Objectives:\n",
    "1. Link `households` to zones to find Nighttime Population and Resident Workers.\n",
    "2. Link `jobs` to zones to find Daytime Jobs.\n",
    "3. Calculate Daytime Population, Surge, and Day/Night Ratio.\n",
    "4. Export the top 15 highest-surge zones to `../output/top_daytime_surge_zones.csv`.\n",
    "5. Plot a choropleth map of the ratio using `../data/zones.json` and save to `../output/day_night_ratio_map.png`."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import pandas as pd\n",
    "import geopandas as gpd\n",
    "import matplotlib.pyplot as plt\n",
    "\n",
    "# Start your analysis here!\n"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/day_night_population.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Ensure Firefox is open and points to the right notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/day_night_population.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/day_night_population.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss popups and maximize browser
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="