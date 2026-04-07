#!/bin/bash
echo "=== Setting up empirical_employment_clustering_dbscan task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Record task start time
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

# Verify data has jobs, buildings, and parcels tables
activate_venv
python -c "
import pandas as pd
jobs = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'jobs')
buildings = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Jobs: {len(jobs)} rows')
print(f'Buildings: {len(buildings)} rows')
print(f'Parcels: {len(parcels)} rows')
assert len(jobs) > 1000, 'Not enough job records'
print('Data verification passed')
"

# Create empty notebook for the task
cat > /home/ga/urbansim_projects/notebooks/employment_clustering.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Empirical Employment Cluster Delineation\n",
    "\n",
    "Identify organic high-density employment clusters using DBSCAN spatial clustering.\n",
    "\n",
    "## Requirements:\n",
    "- Load `jobs`, `buildings`, and `parcels` data from `../data/sanfran_public.h5`\n",
    "- Find buildings with >= 50 jobs and join with parcels to get `x`, `y` coordinates\n",
    "- Run DBSCAN clustering on coordinates with `eps=1500` and `min_samples=5`\n",
    "- Group valid clusters (excluding noise `-1`) and compute `building_count`, `total_jobs`, `centroid_x`, `centroid_y`\n",
    "- Sort by `total_jobs` descending\n",
    "- Save summary to `../output/employment_clusters.csv`\n",
    "- Save a scatter plot mapping all nodes to `../output/cluster_map.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/employment_clustering.ipynb

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
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/employment_clustering.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/employment_clustering.ipynb"
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