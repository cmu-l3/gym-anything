#!/bin/bash
echo "=== Setting up Explore Supply Chain task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_time

# Verify Brightway2 project has data
echo "Verifying Brightway2 project data..."
su - ga -c "export PATH='/opt/miniconda3/bin:\$PATH' && /opt/miniconda3/envs/ab/bin/python -c \"
import brightway2 as bw
bw.projects.set_current('default')
dbs = list(bw.databases)
print('Databases:', dbs)
for db_name in dbs:
    if db_name != 'biosphere3':
        db = bw.Database(db_name)
        print(f'{db_name}: {len(db)} activities')
\"" 2>&1 || echo "WARNING: Project verification returned non-zero"

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

echo "=== Explore Supply Chain task setup complete ==="
echo "The agent should now see Activity Browser with database activities visible."
echo "Task: Find a metal/steel activity, open Graph Explorer, expand 2+ levels."
