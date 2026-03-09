#!/bin/bash
echo "=== Setting up run_location_choice_model task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

activate_venv
python -c "
import pandas as pd
hh = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'households')
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
print(f'Households: {len(hh)} rows, columns: {list(hh.columns)}')
print(f'Buildings: {len(bld)} rows, columns: {list(bld.columns)}')
assert len(hh) > 100, 'Not enough household records'
assert len(bld) > 100, 'Not enough building records'
print('Data verification passed')
"

cat > /home/ga/urbansim_projects/notebooks/location_choice.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Household Location Choice Model\n",
    "\n",
    "Build a logit/MNL model predicting household location choices in San Francisco.\n",
    "\n",
    "## Requirements:\n",
    "- Load households and buildings from `../data/sanfran_public.h5`\n",
    "- Merge datasets on building_id\n",
    "- Use at least 3 features as choice attributes\n",
    "- Save coefficients CSV to `../output/location_choice_coefficients.csv`\n",
    "- Save bar chart to `../output/location_choice_coefficients.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/location_choice.ipynb

echo '{"notebook_exists": true, "csv_exists": false, "plot_exists": false}' > /tmp/initial_state.json

if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/location_choice.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/location_choice.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
