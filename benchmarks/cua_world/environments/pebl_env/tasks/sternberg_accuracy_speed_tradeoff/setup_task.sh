#!/bin/bash
# Setup for sternberg_accuracy_speed_tradeoff task
# Uses real CNP OpenNeuro ds000030 SCAP (Spatial Capacity) data (11 participants)
# Plus one injected participant (sub-99999) with impossible accuracy/RT combination
# Source: Gorgolewski et al. (2017). Scientific Data. doi:10.1038/sdata.2017.93

set -e
echo "=== Setting up sternberg_accuracy_speed_tradeoff task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Copy real SCAP data (with injected contamination) from assets
cp /workspace/assets/scap_data_real.csv /home/ga/pebl/data/sternberg_data.csv
chown ga:ga /home/ga/pebl/data/sternberg_data.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Spatial Working Memory (SCAP) Analysis ===; echo; echo Data file: ~/pebl/data/sternberg_data.csv; echo Output target: ~/pebl/analysis/sternberg_analysis.json; echo; bash' > /tmp/sternberg_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== sternberg_accuracy_speed_tradeoff setup complete ==="
echo "Data: /home/ga/pebl/data/sternberg_data.csv"
echo "Expected output: /home/ga/pebl/analysis/sternberg_analysis.json"
