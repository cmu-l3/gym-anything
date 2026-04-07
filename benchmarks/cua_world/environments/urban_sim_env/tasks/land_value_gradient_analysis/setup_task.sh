#!/bin/bash
echo "=== Setting up land_value_gradient_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Record task start time
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

# Verify necessary tables exist
activate_venv
python -c "
import pandas as pd
store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
tables = store.keys()
assert '/jobs' in tables, 'jobs table missing'
assert '/buildings' in tables, 'buildings table missing'
assert '/parcels' in tables, 'parcels table missing'
store.close()
print('Data verification passed')
"

# Create starting notebook
cat > /home/ga/urbansim_projects/notebooks/bid_rent_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Land Value Gradient and Bid-Rent Analysis\n",
    "\n",
    "Validate the monocentric city Bid-Rent Curve using San Francisco UrbanSim microdata.\n",
    "\n",
    "## Requirements:\n",
    "- Load `jobs`, `buildings`, and `parcels` from `../data/sanfran_public.h5`\n",
    "- Identify the CBD Zone (zone with highest total jobs)\n",
    "- Calculate the (x,y) centroid of the CBD Zone\n",
    "- Compute Euclidean distance from every parcel to the CBD\n",
    "- Compute `value_per_sqft` (avg residential_sales_price / shape_area) for each parcel\n",
    "- Bin distances by 1,000-unit intervals and calculate median value/sqft. Save to `../output/bid_rent_curve.csv`\n",
    "- Find top 50 high-value parcels further than 10,000 units from CBD. Save to `../output/value_anomalies.csv`\n",
    "- Save plot of the bid-rent curve to `../output/bid_rent_chart.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/bid_rent_analysis.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/bid_rent_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/bid_rent_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="