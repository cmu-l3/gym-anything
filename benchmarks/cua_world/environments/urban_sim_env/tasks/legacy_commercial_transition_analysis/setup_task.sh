#!/bin/bash
echo "=== Setting up legacy_commercial_transition_analysis task ==="

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

# Create empty notebook for the task
cat > /home/ga/urbansim_projects/notebooks/neighborhood_transition.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Legacy Commercial & PDR Transition Analysis\n",
    "\n",
    "Identify SF zones where new residential development is encroaching on legacy non-residential space.\n",
    "\n",
    "## Requirements:\n",
    "- Load buildings and parcels from `../data/sanfran_public.h5` and join on `parcel_id`\n",
    "- Group by `zone_id` and compute:\n",
    "  - `legacy_nonres_sqft`: sum of `non_residential_sqft` for buildings built BEFORE 1980\n",
    "  - `new_res_units`: sum of `residential_units` for buildings built IN OR AFTER 2000\n",
    "- Filter zones requiring BOTH: `legacy_nonres_sqft >= 50000` AND `new_res_units >= 50`\n",
    "- Compute `transition_index = new_res_units / (legacy_nonres_sqft / 1000.0)`\n",
    "- Save the Top 15 zones (sorted descending by index) to `../output/transitioning_zones.csv`\n",
    "- Create a scatter plot (`legacy_nonres_sqft` vs `new_res_units`) of ALL filtered zones, highlighting the Top 15.\n",
    "- Save plot to `../output/transition_scatter.png`."
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
chown ga:ga /home/ga/urbansim_projects/notebooks/neighborhood_transition.ipynb

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
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/neighborhood_transition.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/neighborhood_transition.ipynb"
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