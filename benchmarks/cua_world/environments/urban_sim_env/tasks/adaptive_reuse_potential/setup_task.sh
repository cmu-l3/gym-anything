#!/bin/bash
echo "=== Setting up adaptive_reuse_potential task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

activate_venv

# Verify data tables exist
python -c "
import pandas as pd
jobs = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'jobs')
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
print(f'Jobs: {len(jobs)} rows, columns: {list(jobs.columns)}')
print(f'Buildings: {len(bld)} rows, columns: {list(bld.columns)}')
assert len(jobs) > 100, 'Not enough job records'
assert len(bld) > 100, 'Not enough building records'
print('Data verification passed')
"

# Create notebook template
cat > /home/ga/urbansim_projects/notebooks/adaptive_reuse.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Adaptive Reuse Potential Analysis\n",
    "\n",
    "Identify prime candidates for converting underutilized commercial buildings into residential apartments.\n",
    "\n",
    "## Requirements:\n",
    "- Load `buildings` and `jobs` tables from `../data/sanfran_public.h5`\n",
    "- Aggregate jobs by building_id and merge with buildings\n",
    "- Calculate `sqft_per_job` (handle buildings with 0 jobs!)\n",
    "- Filter for: 0 residential units, >= 20,000 non-res sqft, built before 1990, and (0 jobs OR sqft_per_job > 400)\n",
    "- Sort descending by non-res sqft and take the top 100\n",
    "- Save top 100 to `../output/adaptive_reuse_candidates.csv`\n",
    "- Save scatter plot (year_built vs non_residential_sqft) to `../output/reuse_scatter.png`"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import pandas as pd\n",
    "import numpy as np\n",
    "import matplotlib.pyplot as plt\n",
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
chown ga:ga /home/ga/urbansim_projects/notebooks/adaptive_reuse.ipynb

echo '{"notebook_exists": true, "csv_exists": false, "plot_exists": false}' > /tmp/initial_state.json

if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/adaptive_reuse.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/adaptive_reuse.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="