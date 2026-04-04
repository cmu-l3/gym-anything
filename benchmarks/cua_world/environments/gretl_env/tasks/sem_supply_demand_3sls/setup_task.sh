#!/bin/bash
set -euo pipefail

echo "=== Setting up Simultaneous Equations (3SLS) Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Ensure 'truffles.gdt' is available
# ==============================================================================
DATASET="truffles.gdt"
TARGET_PATH="/home/ga/Documents/gretl_data/$DATASET"
POE5_SRC="/opt/gretl_data/poe5/$DATASET"

mkdir -p "/home/ga/Documents/gretl_data"
mkdir -p "/home/ga/Documents/gretl_output"
chown ga:ga "/home/ga/Documents/gretl_output"

if [ -f "$POE5_SRC" ]; then
    echo "Copying $DATASET from POE5 data..."
    cp "$POE5_SRC" "$TARGET_PATH"
else
    echo "Creating $DATASET from embedded data (backup)..."
    # Create valid XML for truffles.gdt if missing (Simulation of market data)
    # This ensures the task is runnable even if the specific POE5 file is missing
    cat > "$TARGET_PATH" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE gretldata SYSTEM "gretldata.dtd">
<gretldata name="truffles" frequency="1" startobs="1" endobs="30" type="cross-section">
<description>
Market data for truffles (Simulated based on Gujarati/POE structure).
q = quantity traded
p = market price
ps = price of substitute
di = disposable income
pf = price of factor of production
</description>
<variables count="5">
<variable name="q" label="Quantity"/>
<variable name="p" label="Price"/>
<variable name="ps" label="Price of Substitute"/>
<variable name="di" label="Disposable Income"/>
<variable name="pf" label="Factor Price"/>
</variables>
<observations count="30" labels="false">
<obs> 10.3 50.1 20.5 3000 12.0 </obs>
<obs> 9.8 55.2 21.0 2900 12.5 </obs>
<obs> 11.2 48.0 19.5 3100 11.8 </obs>
<obs> 10.5 52.3 20.0 3050 12.2 </obs>
<obs> 9.5 58.0 22.0 2950 13.0 </obs>
<obs> 12.0 45.0 18.0 3200 11.0 </obs>
<obs> 10.1 51.5 20.2 3010 12.1 </obs>
<obs> 10.8 49.2 19.8 3080 11.9 </obs>
<obs> 9.2 60.1 22.5 2850 13.5 </obs>
<obs> 11.5 46.5 18.5 3150 11.2 </obs>
<obs> 10.4 50.8 20.3 3020 12.0 </obs>
<obs> 9.9 54.0 21.2 2920 12.8 </obs>
<obs> 11.0 47.5 19.0 3120 11.5 </obs>
<obs> 10.2 51.2 20.1 3030 12.1 </obs>
<obs> 9.6 57.5 21.8 2960 12.9 </obs>
<obs> 11.8 45.8 18.2 3180 11.1 </obs>
<obs> 10.0 53.0 20.8 2980 12.6 </obs>
<obs> 10.6 49.8 19.9 3060 11.9 </obs>
<obs> 9.3 59.0 22.2 2880 13.2 </obs>
<obs> 11.4 46.2 18.8 3140 11.3 </obs>
<obs> 10.3 50.5 20.4 3015 12.0 </obs>
<obs> 9.7 56.0 21.5 2940 12.7 </obs>
<obs> 11.1 47.0 19.2 3110 11.6 </obs>
<obs> 10.5 52.0 20.0 3040 12.3 </obs>
<obs> 9.4 58.5 22.1 2900 13.1 </obs>
<obs> 11.9 45.5 18.1 3190 11.0 </obs>
<obs> 10.1 51.8 20.2 3005 12.2 </obs>
<obs> 10.7 49.5 19.7 3070 11.8 </obs>
<obs> 9.1 60.5 22.6 2840 13.6 </obs>
<obs> 11.6 46.0 18.6 3160 11.2 </obs>
</observations>
</gretldata>
EOF
    echo "Created simulated $DATASET."
fi

chown ga:ga "$TARGET_PATH"
chmod 644 "$TARGET_PATH"

# ==============================================================================
# 2. Launch Gretl
# ==============================================================================
kill_gretl
launch_gretl "$TARGET_PATH" "/home/ga/gretl_task.log"
wait_for_gretl 60 || true
sleep 3

# Dismiss dialogs
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

maximize_gretl
focus_gretl

# ==============================================================================
# 3. Capture Initial State
# ==============================================================================
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="