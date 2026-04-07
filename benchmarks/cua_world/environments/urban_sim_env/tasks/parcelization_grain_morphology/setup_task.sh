#!/bin/bash
echo "=== Setting up parcelization_grain_morphology task ==="

source /workspace/scripts/task_utils.sh

# Create output directories and set permissions
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

# Verify data has required tables
activate_venv
python -c "
import pandas as pd
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
buildings = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
jobs = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'jobs')
print(f'Parcels: {len(parcels)} rows')
print(f'Buildings: {len(buildings)} rows')
print(f'Jobs: {len(jobs)} rows')
assert len(parcels) > 100, 'Not enough parcel records'
print('Data verification passed')
"

# Create initial notebook with instructions
cat > /home/ga/urbansim_projects/notebooks/parcelization_morphology.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Urban Morphology and Parcelization Grain Analysis\n",
    "\n",
    "Classify San Francisco planning zones into morphological categories based on parcel sizes, and analyze how \"grain\" affects housing and job density.\n",
    "\n",
    "## Requirements:\n",
    "- Load `parcels`, `buildings`, and `jobs` from `../data/sanfran_public.h5`\n",
    "- Exclude parcels where `parcel_acres` is missing or `0`\n",
    "- Aggregate data to `zone_id`: calculate total parcels, average/sum parcel acres, total residential units, total jobs.\n",
    "- Filter out zones with fewer than **20 parcels**.\n",
    "- Categorize zones by `avg_parcel_acres` into a new `grain_category` column:\n",
    "  * `Fine-Grain`: < 0.15 acres\n",
    "  * `Medium-Grain`: 0.15 to < 0.5 acres\n",
    "  * `Coarse-Grain`: 0.5 to < 2.0 acres\n",
    "  * `Superblock`: >= 2.0 acres\n",
    "- Calculate `units_per_acre` and `jobs_per_acre` for each zone.\n",
    "- Save the zone-level DataFrame to `../output/zone_morphology.csv`\n",
    "- Create a summary DataFrame grouping by `grain_category` computing the **mean** density metrics, and save to `../output/grain_summary.csv`\n",
    "- Save a grouped bar chart of the summary data to `../output/morphology_density_chart.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/parcelization_morphology.ipynb

# Record initial state for export comparison
echo '{"notebook_exists": true, "zone_csv_exists": false, "summary_csv_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox pointing to the newly created notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/parcelization_morphology.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox session to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/parcelization_morphology.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss popups, maximize window
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="