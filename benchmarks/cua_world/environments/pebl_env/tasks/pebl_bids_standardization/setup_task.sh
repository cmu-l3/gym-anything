#!/bin/bash
set -e

echo "=== Setting up PEBL BIDS Standardization Task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

RAW_DIR="/home/ga/pebl/raw_data"
mkdir -p "$RAW_DIR"

# Randomize 3 subject IDs to prevent hardcoding (anti-gaming)
ID1=$(printf "%02d" $((RANDOM % 90 + 10)))
ID2=$(printf "%02d" $((RANDOM % 90 + 10)))
ID3=$(printf "%02d" $((RANDOM % 90 + 10)))

# Ensure uniqueness
while [ "$ID1" = "$ID2" ] || [ "$ID1" = "$ID3" ] || [ "$ID2" = "$ID3" ]; do
    ID2=$(printf "%02d" $((RANDOM % 90 + 10)))
    ID3=$(printf "%02d" $((RANDOM % 90 + 10)))
done

# Save ground truth IDs securely (hidden from agent)
echo "[\"$ID1\", \"$ID2\", \"$ID3\"]" > /tmp/ground_truth_ids.json
chmod 600 /tmp/ground_truth_ids.json

echo "Generated dynamic participant IDs: $ID1, $ID2, $ID3"

cd "$RAW_DIR"

# Download real PEBL sample data to ensure non-synthetic distributions
# Fallbacks included in case of network unavailability during setup
wget -qO bart.csv "https://raw.githubusercontent.com/stmueller/pebl/master/battery/bart/data/bart-sample.csv" || touch bart.csv
wget -qO flanker.csv "https://raw.githubusercontent.com/stmueller/pebl/master/battery/flanker/data/flanker-sample.csv" || touch flanker.csv
wget -qO simon.csv "https://raw.githubusercontent.com/stmueller/pebl/master/battery/simon/data/simon-sample.csv" || touch simon.csv
wget -qO wcst.csv "https://raw.githubusercontent.com/stmueller/pebl/master/battery/bcst/data/bcst-sample.csv" || touch wcst.csv

for task in bart flanker simon wcst; do
    if [ ! -s "${task}.csv" ]; then
        if [ -f "/workspace/assets/${task}_data_real.csv" ]; then
            cp "/workspace/assets/${task}_data_real.csv" "${task}.csv"
        else
            # Emergency minimal fallback if strictly offline and assets missing
            echo "participant,trial,rt,correct" > "${task}.csv"
            echo "1,1,450,1" >> "${task}.csv"
            echo "1,2,520,1" >> "${task}.csv"
            echo "1,3,480,0" >> "${task}.csv"
        fi
    fi
done

# Create demographics.csv
cat << EOF > demographics.csv
id,age,sex,group
$ID1,22,F,control
$ID2,25,M,treatment
$ID3,19,F,control
EOF

# Create messy raw files and inject the randomized IDs into the file contents (column 1)
for id in $ID1 $ID2 $ID3; do
    awk -v id="$id" 'BEGIN{FS=OFS=","} NR==1{print} NR>1{$1=id; print}' bart.csv > "P${id}_bart_raw.csv"
    awk -v id="$id" 'BEGIN{FS=OFS=","} NR==1{print} NR>1{$1=id; print}' flanker.csv > "P${id}_flanker_data.csv"
    awk -v id="$id" 'BEGIN{FS=OFS=","} NR==1{print} NR>1{$1=id; print}' simon.csv > "P${id}_simon_out.csv"
    awk -v id="$id" 'BEGIN{FS=OFS=","} NR==1{print} NR>1{$1=id; print}' wcst.csv > "P${id}_wcst_log.csv"
done

# Cleanup base files
rm bart.csv flanker.csv simon.csv wcst.csv

chown -R ga:ga /home/ga/pebl
chmod -R 755 /home/ga/pebl

# Record start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === PEBL BIDS Standardization Task ===; echo; echo Raw Data: ~/pebl/raw_data/; echo Target: ~/pebl/bids_dataset/; echo; ls -l ~/pebl/raw_data/; echo; bash' > /tmp/bids_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== PEBL BIDS Standardization setup complete ==="