#!/bin/bash
echo "=== Setting up model_mhk_tidal_array task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/tidal_array_model.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/tidal_array_results.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/parsed_json.json 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Ensure a terminal is available for the agent (since this is a scripting task)
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 3
    
    # Maximize terminal
    DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

echo "=== Task setup complete ==="