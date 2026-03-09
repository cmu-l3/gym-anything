#!/bin/bash
set -euo pipefail
echo "=== Setting up Panel Hausman Test task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
OUTPUT_DIR="/home/ga/Documents/gretl_output"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Prepare the Data: Grunfeld Investment Data
# We need to ensure it exists as a CSV for the agent to load
DATA_DIR="/home/ga/Documents/gretl_data"
mkdir -p "$DATA_DIR"
CSV_PATH="$DATA_DIR/grunfeld.csv"

# Check if we have the native gretl file to convert, or create it raw
# Grunfeld is a standard dataset usually included, but we'll recreate the CSV header/structure
# to ensure it matches the task description perfectly if the system one is missing.

echo "Creating Grunfeld CSV dataset..."
# We will use python to generate the CSV from the installed gretl data if possible,
# or download/write it. Since we can't rely on external downloads during setup in all envs,
# we'll look for the system copy first.

GDT_PATH=$(find /usr/share/gretl -name "grunfeld.gdt" 2>/dev/null | head -1)

if [ -f "$GDT_PATH" ]; then
    echo "Converting system grunfeld.gdt to CSV..."
    # Use gretlcli to export
    su - ga -c "gretlcli -e 'open \"$GDT_PATH\"; store \"$CSV_PATH\" --csv'" >/dev/null
else
    echo "System grunfeld.gdt not found. Downloading/Creating..."
    # Fallback: Create CSV directly (small enough subset or full if possible, but simplest is to try to get it)
    # Since we can't easily hardcode 200 rows here, we'll try to find it in the POE5 data we installed in the env
    # POE5 often has 'invest.gdt' or similar.
    # If not, we will assume the environment installation provided standard datasets.
    
    # Emergency fallback: Create a dummy CSV structure so the agent sees the file 
    # (The verifier checks for specific values, so we really need the real data. 
    # The environment install script installs 'gretl' package which includes grunfeld.gdt)
    
    # Try one more location
    if [ -f "/opt/gretl_data/poe5/grunfeld.gdt" ]; then
         su - ga -c "gretlcli -e 'open \"/opt/gretl_data/poe5/grunfeld.gdt\"; store \"$CSV_PATH\" --csv'" >/dev/null
    else
         # Download if network is available (allowed in setup)
         wget -q -O "$DATA_DIR/grunfeld.csv" "https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/plm/Grunfeld.csv"
         # Rdatasets version has headers: "","firm","year","inv","value","capital"
         # Task expects: firm, year, invest, mvalue, kstock
         # We need to fix headers
         sed -i '1s/^.*$/row,firm,year,invest,mvalue,kstock/' "$DATA_DIR/grunfeld.csv"
    fi
fi

# Ensure permissions
chown ga:ga "$CSV_PATH"
chmod 644 "$CSV_PATH"

# Verify data exists
if [ ! -f "$CSV_PATH" ]; then
    echo "ERROR: Failed to create grunfeld.csv"
    exit 1
fi

echo "Data prepared at $CSV_PATH"

# Launch Gretl to initial state
kill_gretl
launch_gretl "" "/home/ga/gretl_startup.log"

# Wait for window
wait_for_gretl 60
maximize_gretl

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="