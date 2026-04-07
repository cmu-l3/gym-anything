#!/bin/bash
# Setup for cnp_multi_task_battery_report task
# Copies existing CNP assets into the task data directory
# The key challenges: (1) SCAP IDs lack hyphens, (2) sub-99999 is contaminated in BART+SS

set -e
echo "=== Setting up cnp_multi_task_battery_report task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data/cnp
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Copy existing CNP data assets
cp /workspace/assets/bart_data_real.csv /home/ga/pebl/data/cnp/bart_data.csv
cp /workspace/assets/stopsignal_data_real.csv /home/ga/pebl/data/cnp/stopsignal_data.csv
cp /workspace/assets/scap_data_real.csv /home/ga/pebl/data/cnp/scap_data.csv

chown -R ga:ga /home/ga/pebl/data/cnp
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x38 -- bash -c '
echo \"=== CNP Multi-Task Cognitive Battery Report ===\"
echo \"\"
echo \"Data files:\"
echo \"  ~/pebl/data/cnp/bart_data.csv        (BART: pumps, exploded per trial)\"
echo \"  ~/pebl/data/cnp/stopsignal_data.csv  (Stop Signal: go RT, SSD, outcome)\"
echo \"  ~/pebl/data/cnp/scap_data.csv        (SCAP: set_size, correct, RT)\"
echo \"\"
echo \"Output: ~/pebl/analysis/cnp_battery_report.json\"
echo \"\"
echo \"Note: Check participant ID formats carefully across datasets.\"
echo \"\"
bash' > /tmp/cnp_terminal.log 2>&1 &"

# Wait for terminal
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== cnp_multi_task_battery_report setup complete ==="
echo "BART data: /home/ga/pebl/data/cnp/bart_data.csv (11 real + sub-99999 contaminated)"
echo "SS data:   /home/ga/pebl/data/cnp/stopsignal_data.csv"
echo "SCAP data: /home/ga/pebl/data/cnp/scap_data.csv (ID format: sub10159 not sub-10159)"
