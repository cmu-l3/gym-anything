#!/bin/bash
echo "=== Setting up Dynamic Panel Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/gretl_data
mkdir -p /home/ga/Documents/gretl_output
chown -R ga:ga /home/ga/Documents

# CLEAN START: Remove the target dataset if it exists to force download
rm -f /home/ga/Documents/gretl_data/abdata.gdt
# Remove any previous results
rm -f /home/ga/Documents/gretl_output/dynamic_panel.inp
rm -f /home/ga/Documents/gretl_output/dpanel_results.txt
rm -f /home/ga/Documents/gretl_output/ar2_pvalue.txt

echo "Cleaned previous data and results."

# Launch Gretl (empty)
# We use the utility function but pass no dataset to start empty
echo "Launching Gretl..."
launch_gretl "" "/home/ga/gretl_setup.log"

# Wait for window
wait_for_gretl 60

# Maximize and focus
maximize_gretl
focus_gretl

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="