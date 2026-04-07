#!/bin/bash
# Setup for bart_risk_adjustment_report task
# Uses real CNP OpenNeuro ds000030 BART data (11 participants: sub-10159 to sub-10304)
# Plus one injected participant (sub-99999) with impossible data (pumps=0 on all trials)
# Source: Gorgolewski et al. (2017). Scientific Data. doi:10.1038/sdata.2017.93

set -e
echo "=== Setting up bart_risk_adjustment_report task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Copy real BART data (with injected contamination) from assets
cp /workspace/assets/bart_data_real.csv /home/ga/pebl/data/bart_data.csv
chown ga:ga /home/ga/pebl/data/bart_data.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === BART Risk Adjustment Analysis ===; echo; echo Data file: ~/pebl/data/bart_data.csv; echo Output target: ~/pebl/analysis/bart_report.json; echo; bash' > /tmp/bart_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== bart_risk_adjustment_report setup complete ==="
echo "Data: /home/ga/pebl/data/bart_data.csv"
echo "Expected output: /home/ga/pebl/analysis/bart_report.json"
