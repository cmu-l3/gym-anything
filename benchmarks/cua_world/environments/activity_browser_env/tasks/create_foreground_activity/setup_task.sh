#!/bin/bash
echo "=== Setting up Create Foreground Activity task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_time

# Clean up any previously created foreground database (ensure fresh start)
echo "Cleaning up any previous My_Foreground database..."
su - ga -c "export PATH='/opt/miniconda3/bin:\$PATH' && /opt/miniconda3/envs/ab/bin/python -c \"
import brightway2 as bw
bw.projects.set_current('default')
if 'My_Foreground' in bw.databases:
    del bw.databases['My_Foreground']
    print('Removed existing My_Foreground database')
else:
    print('No existing My_Foreground database to remove')
print('Current databases:', list(bw.databases))
\"" 2>&1 || echo "WARNING: Cleanup returned non-zero"

# Launch Activity Browser
echo "Launching Activity Browser..."
launch_ab

# Wait for full UI load
sleep 5

# Focus and maximize
focus_ab
maximize_ab
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Create Foreground Activity task setup complete ==="
echo "The agent should now see Activity Browser ready to create a new database."
echo "Task: Create 'My_Foreground' database, add 'Recycled Aluminum Production' activity with exchanges."
