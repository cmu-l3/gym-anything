#!/bin/bash
echo "=== Setting up land_value_capture_levy_analysis task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

date +%s > /home/ga/.task_start_time

if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

activate_venv
python -c "
import pandas as pd
jobs = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'jobs')
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
print(f'Jobs: {len(jobs)} rows')
print(f'Buildings: {len(bld)} rows')
assert len(jobs) > 100
assert len(bld) > 100
print('Data verification passed')
"

cat > /home/ga/urbansim_projects/notebooks/lvc_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Land Value Capture & Betterment Levy Analysis\n",
    "\n",
    "Simulate a land value capture policy for San Francisco.\n",
    "\n",
    "## Requirements:\n",
    "- Load `jobs`, `buildings`, `parcels`, `zoning` from `../data/sanfran_public.h5`\n",
    "- Identify Top 5 zones with the highest total employment.\n",
    "- Filter parcels to only those in the top 5 zones.\n",
    "- Join zoning to get `max_far` (use 1.0 if NaN or <= 0). Baseline sqft = shape_area * max_far.\n",
    "- Calculate total `residential_sales_price` per parcel. Drop if 0/NaN. Value/sqft = total_value / baseline_sqft.\n",
    "- Simulate adding 2.5 to Max FAR. New sqft = shape_area * 2.5. Uplift = new sqft * value/sqft.\n",
    "- Levy = 25% of Uplift.\n",
    "- Group by zone_id. Save CSV to `../output/lvc_revenue_by_zone.csv` (Columns: zone_id, total_parcels_assessed, total_value_uplift, projected_levy_revenue).\n",
    "- Save bar chart to `../output/lvc_revenue_chart.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/lvc_analysis.ipynb

if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/lvc_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/lvc_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="