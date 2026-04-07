#!/bin/bash
echo "=== Setting up ev_charging_allocation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Create necessary directories
mkdir -p /home/ga/urbansim_projects/output
chown -R ga:ga /home/ga/urbansim_projects/output

# Verify required data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF UrbanSim data not found"
    exit 1
fi

# Pre-check data to assure target tables exist
activate_venv
python -c "
import pandas as pd
h5_path = '/home/ga/urbansim_projects/data/sanfran_public.h5'
hh = pd.read_hdf(h5_path, 'households')
bld = pd.read_hdf(h5_path, 'buildings')
parcels = pd.read_hdf(h5_path, 'parcels')
print(f'Households: {len(hh)}, Buildings: {len(bld)}, Parcels: {len(parcels)}')
assert 'cars' in hh.columns, 'Missing cars column'
assert 'residential_units' in bld.columns, 'Missing residential_units column'
assert 'zone_id' in parcels.columns, 'Missing zone_id column'
print('Data verification passed')
"

# Create starter notebook
cat > /home/ga/urbansim_projects/notebooks/ev_charging_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Public EV Charging Infrastructure Allocation\n",
    "\n",
    "Identify zones with the highest concentration of \"charging-vulnerable\" households.\n",
    "\n",
    "## Requirements:\n",
    "- Load households, buildings, parcels from `../data/sanfran_public.h5`\n",
    "- Link households -> buildings -> parcels to get `residential_units` and `zone_id`\n",
    "- Identify vulnerable households (`cars >= 1` AND `residential_units >= 5`)\n",
    "- Compute `total_households`, `vuln_households`, and `vuln_pct` by `zone_id`\n",
    "- Filter to zones with `>= 100` total households\n",
    "- Rank by `vuln_pct` descending and export top 20 to `../output/ev_charging_priority_zones.csv`\n",
    "- Save scatter plot to `../output/ev_vulnerability_scatter.png`"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Write your analysis code here\n"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/ev_charging_analysis.ipynb

# Launch Jupyter Lab if not running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Launch Firefox focused on the notebook
if ! is_firefox_running; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/ev_charging_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    echo "Navigating existing Firefox..."
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/ev_charging_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Ensure focus and maximize
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial state screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="