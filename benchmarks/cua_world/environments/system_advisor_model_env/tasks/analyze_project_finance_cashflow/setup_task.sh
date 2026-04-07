#!/bin/bash
echo "=== Setting up project finance cash flow task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
date +%s > /home/ga/.task_start_time

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/SAM_Projects
rm -f /home/ga/Documents/SAM_Projects/daggett_100mw_finance.json
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Ensure PySAM is available
if ! python3 -c "import PySAM.Pvwattsv8; import PySAM.Singleowner" 2>/dev/null; then
    echo "WARNING: PySAM modules not found in default path."
fi

# Locate solar resource directory to assist agent
SOLAR_RES=""
if [ -f /home/ga/.SAM/solar_resource_dir.txt ]; then
    SOLAR_RES=$(cat /home/ga/.SAM/solar_resource_dir.txt)
fi

# Write a quick hint file to the desktop for the agent
cat > /home/ga/Desktop/Task_Hint.txt << EOF
Project Finance Analysis Task Hints:
- You need to use PySAM to run a Pvwattsv8 model coupled with a Singleowner financial model.
- Weather files are located at: ${SOLAR_RES:-/opt/SAM/solar_resource}
- You'll likely need to search the weather directory for "daggett" to find the exact CSV filename.
- Remember to configure all specified financial inputs on the Singleowner model before executing it.
- Your output must be saved to: /home/ga/Documents/SAM_Projects/daggett_100mw_finance.json
EOF
chown ga:ga /home/ga/Desktop/Task_Hint.txt

# Ensure terminal is available
if ! pgrep -u ga gnome-terminal > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 --working-directory=/home/ga 2>/dev/null &"
    sleep 3
fi

# Focus terminal and maximize
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot showing terminal ready
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="