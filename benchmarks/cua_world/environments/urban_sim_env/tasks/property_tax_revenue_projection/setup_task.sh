#!/bin/bash
echo "=== Setting up property_tax_revenue_projection task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify SF data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

activate_venv

# Verify data tables required for the task
python -c "
import pandas as pd
store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
assert 'buildings' in store, 'buildings table missing'
assert 'parcels' in store, 'parcels table missing'
store.close()
print('Data verification passed')
"

# Create notebook template
cat > /home/ga/urbansim_projects/notebooks/tax_revenue_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Property Tax Revenue Projection by Zone\n",
    "\n",
    "Analyze estimated annual property tax revenue and fiscal productivity (tax per acre) for San Francisco planning zones.\n",
    "\n",
    "## Requirements:\n",
    "- Load `buildings` and `parcels` from `../data/sanfran_public.h5`\n",
    "- Exclude buildings missing `residential_sales_price` or with 0 value\n",
    "- Join buildings to parcels to get `zone_id` and parcel acreage\n",
    "- Apply 1.17% (0.0117) tax rate to assessed values\n",
    "- Aggregate totals by `zone_id`\n",
    "- Save zone summary to `../output/zone_tax_revenue.csv`\n",
    "- Save top 15 zones bar chart to `../output/tax_revenue_top_zones.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/tax_revenue_analysis.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/tax_revenue_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox window
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/tax_revenue_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss dialogs, maximize, and take screenshot
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="