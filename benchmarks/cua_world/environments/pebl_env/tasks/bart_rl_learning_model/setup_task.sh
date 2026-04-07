#!/bin/bash
# Setup for bart_rl_learning_model task
# Copies BART data asset to task data directory
# The agent must fit an RL model and exclude the contaminated participant

set -e
echo "=== Setting up bart_rl_learning_model task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data/bart
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Copy BART data from assets
cp /workspace/assets/bart_data_real.csv /home/ga/pebl/data/bart/bart_data.csv
chown ga:ga /home/ga/pebl/data/bart/bart_data.csv

date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open terminal
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x38 -- bash -c '
echo \"=== BART Reinforcement Learning Model Fitting ===\"
echo \"\"
echo \"Data:   ~/pebl/data/bart/bart_data.csv\"
echo \"Output: ~/pebl/analysis/bart_rl_report.json\"
echo \"\"
echo \"Model: Delta-learning RL (Wallsten et al. 2005)\"
echo \"  p_new = p_old + alpha*(1-p_old)   [if exploded]\"
echo \"  p_new = p_old*(1-alpha)            [if not exploded]\"
echo \"  predicted_pumps = floor(1/p) - 1\"
echo \"  Fit alpha in [0.001, 0.999] by minimizing MSE\"
echo \"\"
echo \"Note: Identify and exclude the contaminated participant first.\"
echo \"\"
bash' > /tmp/bart_rl_terminal.log 2>&1 &"

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

echo "=== bart_rl_learning_model setup complete ==="
echo "Data: /home/ga/pebl/data/bart/bart_data.csv"
echo "Contaminated: sub-99999 (ADJMEANPUMPS=0 on non-exploded trials)"
