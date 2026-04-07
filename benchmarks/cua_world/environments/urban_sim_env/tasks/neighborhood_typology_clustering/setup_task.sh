#!/bin/bash
echo "=== Setting up neighborhood typology clustering task ==="

source /workspace/scripts/task_utils.sh

# Ensure clean output directory
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
rm -f /home/ga/urbansim_projects/output/zone_typologies.csv
rm -f /home/ga/urbansim_projects/output/cluster_profiles.png
rm -f /home/ga/urbansim_projects/notebooks/neighborhood_typology.ipynb

chown -R ga:ga /home/ga/urbansim_projects/output
chown -R ga:ga /home/ga/urbansim_projects/notebooks

# Record task start time
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    if [ -f /opt/urbansim_data/sanfran_public.h5 ]; then
        cp /opt/urbansim_data/sanfran_public.h5 /home/ga/urbansim_projects/data/
        chown ga:ga /home/ga/urbansim_projects/data/sanfran_public.h5
    else
        exit 1
    fi
fi

# Verify data tables
activate_venv
python -c "
import pandas as pd
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Buildings: {len(bld)} rows')
print(f'Parcels: {len(parcels)} rows')
assert 'zone_id' in parcels.columns, 'zone_id missing from parcels'
assert len(bld) > 100, 'Not enough building records'
print('Data verification passed')
"

# Create a notebook template for the agent
cat > /home/ga/urbansim_projects/notebooks/neighborhood_typology.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Neighborhood Typology Clustering\n",
    "\n",
    "Classify San Francisco's zones into 5 neighborhood typologies.\n",
    "\n",
    "## Requirements:\n",
    "- Load `buildings` and `parcels` from `../data/sanfran_public.h5`\n",
    "- Join buildings with parcels to get `zone_id`\n",
    "- Aggregate building features to the zone level (mean year built, sum of residential units, etc.)\n",
    "- Standardize features and apply K-Means clustering (k=5, random_state=42)\n",
    "- Save the zone-level clustering results to `../output/zone_typologies.csv`\n",
    "- Save a bar chart of cluster profiles to `../output/cluster_profiles.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/neighborhood_typology.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/neighborhood_typology.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/neighborhood_typology.ipynb"
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