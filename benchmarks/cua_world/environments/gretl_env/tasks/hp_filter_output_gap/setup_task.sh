#!/bin/bash
set -e
echo "=== Setting up HP Filter Output Gap Analysis ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up and prepare output directory
rm -rf /home/ga/Documents/gretl_output
mkdir -p /home/ga/Documents/gretl_output
chown ga:ga /home/ga/Documents/gretl_output

# 2. Setup the task with usa.gdt
# This kills gretl, restores the dataset, launches gretl, and takes a screenshot
setup_gretl_task "usa.gdt" "hp_setup"

# 3. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="
echo "Task: HP Filter Analysis on usa.gdt"
echo "Target Directory: /home/ga/Documents/gretl_output/"