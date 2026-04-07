#!/bin/bash
echo "=== Setting up underbuilt_parcel_analysis task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Ensure output directory exists and is owned by the agent
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Verify required data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at expected path."
    exit 1
fi

# Activate virtual environment and quickly verify data access
activate_venv
python -c "
import pandas as pd
store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
assert 'buildings' in store.keys() and 'parcels' in store.keys()
store.close()
print('Data verification passed')
"

# Create a starter Jupyter notebook
cat > /home/ga/urbansim_projects/notebooks/soft_site_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Underbuilt Parcel Analysis (Soft Sites)\n",
    "\n",
    "Calculate Floor Area Ratio (FAR) across San Francisco to identify soft sites for potential redevelopment.\n",
    "\n",
    "## Requirements:\n",
    "- Load `buildings` and `parcels` from `../data/sanfran_public.h5`\n",
    "- Calculate total `building_sqft` per parcel\n",
    "- Calculate FAR (`building_sqft` / `parcel_sqft`)\n",
    "- Filter Soft Sites: `parcel_sqft` >= 5000, `existing_far` < 0.5, and `existing_far` > 0.01\n",
    "- Aggregate by `zone_id` (count and total sqft of soft sites)\n",
    "- Save Top 20 zones to `../output/top_soft_sites.csv`\n",
    "- Save bar chart of top 20 to `../output/soft_sites_chart.png`\n",
    "- Save summary JSON to `../output/soft_sites_summary.json`"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Write your code here\n",
    "import pandas as pd\n",
    "import json\n",
    "import matplotlib.pyplot as plt\n"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/soft_site_analysis.ipynb

# Start Jupyter Lab if it's not running
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Ensure Firefox is open to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/soft_site_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/soft_site_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Maximize and clear potential dialogs
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot for reference
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="