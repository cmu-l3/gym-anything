#!/bin/bash
echo "=== Setting up service_worker_spatial_mismatch task ==="

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
hh = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'households')
jobs = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'jobs')
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
print(f'Households: {len(hh)} rows, columns: {list(hh.columns)}')
print(f'Jobs: {len(jobs)} rows, columns: {list(jobs.columns)}')
print(f'Buildings: {len(bld)} rows, columns: {list(bld.columns)}')
assert len(hh) > 100
assert len(jobs) > 100
assert len(bld) > 100
print('Data verification passed')
"

cat > /home/ga/urbansim_projects/notebooks/spatial_mismatch_instructions.md << 'EOF'
# Service Sector Job-Housing Spatial Mismatch

Analyze the spatial mismatch between service sector jobs and low-income housing availability across San Francisco zones.

## Requirements:
- Create a notebook `spatial_mismatch.ipynb`.
- Load `households`, `jobs`, and `buildings` tables from `../data/sanfran_public.h5`.
- Join `households` and `jobs` to their `zone_id` using `building_id` in the `buildings` table.
- Calculate the 25th percentile of `income` across all households. Filter households with `income <= threshold` and count per zone.
- Filter `jobs` where `sector_id` is 4 or 10. Count per zone.
- Merge these zone counts (fill missing with 0).
- Calculate `mismatch_ratio = service_jobs / (low_income_hhs + 1)`.
- Filter for zones with at least 100 service jobs.
- Sort by `mismatch_ratio` descending.
- Export Top 30 worst mismatch zones to `../output/worst_mismatch_zones.csv` with columns: `zone_id`, `service_jobs`, `low_income_hhs`, `mismatch_ratio`.
- Create a scatter plot of all significant zones (low_income_hhs vs service_jobs), highlighting the top 30, and save to `../output/mismatch_scatter.png`.
EOF

chown ga:ga /home/ga/urbansim_projects/notebooks/spatial_mismatch_instructions.md

if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="