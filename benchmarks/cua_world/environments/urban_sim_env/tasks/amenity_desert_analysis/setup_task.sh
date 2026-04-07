#!/bin/bash
echo "=== Setting up amenity_desert_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
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

activate_venv

# Create a starter notebook
cat > /home/ga/urbansim_projects/notebooks/amenity_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Neighborhood Amenity Desert Analysis\n",
    "\n",
    "Identify SF zones lacking non-residential spaces relative to their population.\n",
    "\n",
    "## Task Requirements:\n",
    "- Load `households`, `buildings`, and `parcels` from `../data/sanfran_public.h5`\n",
    "- Group total `persons` (from households) and `non_residential_sqft` (from buildings) by `zone_id`\n",
    "- Filter to zones with `total_persons >= 500`\n",
    "- Calculate `amenity_sqft_per_capita`\n",
    "- Classify into: `Amenity Desert` (<50), `Moderate Access` (50-200), `Amenity Rich` (>=200)\n",
    "- Save CSV to `../output/amenity_deserts.csv`\n",
    "- Save plot to `../output/amenity_category_distribution.png`\n",
    "- Save JSON to `../output/amenity_summary.json` with keys: `total_amenity_deserts`, `desert_population`, `highest_amenity_zone_id`"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import pandas as pd\n",
    "import matplotlib.pyplot as plt\n",
    "import json\n",
    "\n",
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
chown ga:ga /home/ga/urbansim_projects/notebooks/amenity_analysis.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox pointing to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/amenity_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/amenity_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot showing environment setup
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="