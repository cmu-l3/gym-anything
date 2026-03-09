#!/bin/bash
set -e
echo "=== Setting up audit_benford_population task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create JASP documents directory
mkdir -p /home/ga/Documents/JASP

# 1. Prepare Data
# Download real World Bank population data
# We use a reliable mirror or the original dataset
DATA_URL="https://raw.githubusercontent.com/datasets/population/master/data/population.csv"
RAW_FILE="/tmp/population_raw.csv"
TARGET_FILE="/home/ga/Documents/JASP/population_2018.csv"

echo "Downloading population data..."
if curl -L -o "$RAW_FILE" "$DATA_URL" --max-time 30; then
    echo "Filtering for year 2018..."
    # Header: Country Name,Country Code,Year,Value
    # Filter for 2018 and ensure we have data. 
    # Note: The CSV structure might vary, but standard dataset usually has header.
    head -n 1 "$RAW_FILE" > "$TARGET_FILE"
    grep ",2018," "$RAW_FILE" >> "$TARGET_FILE" || true
    
    # Check if we have enough data (at least 100 rows)
    LINE_COUNT=$(wc -l < "$TARGET_FILE")
    if [ "$LINE_COUNT" -lt 100 ]; then
        echo "WARNING: Downloaded data too small. Using fallback generation."
        USE_FALLBACK=true
    else
        echo "Data prepared: $LINE_COUNT rows."
        USE_FALLBACK=false
    fi
else
    echo "WARNING: Download failed. Using fallback."
    USE_FALLBACK=true
fi

# Fallback: Generate real-looking data based on Benford's law if download fails
# (Only used if network fails to ensure task is playable)
if [ "$USE_FALLBACK" = "true" ]; then
    echo "Country Name,Country Code,Year,Value" > "$TARGET_FILE"
    # Generate 200 records with exponential distribution (naturally follows Benford)
    python3 -c "
import random
import math
countries = ['Land_' + str(i) for i in range(200)]
for i, c in enumerate(countries):
    # Exponential growth simulation
    val = int(1000 * math.exp(random.uniform(0, 10)))
    print(f'{c},C{i},2018,{val}')
" >> "$TARGET_FILE"
fi

chown ga:ga "$TARGET_FILE"

# 2. Launch JASP
echo "Starting JASP..."
pkill -f "org.jaspstats.JASP" 2>/dev/null || true

# Launch JASP empty (as per Description "Starting State: JASP is open with no data loaded")
# We use the launcher script created in env setup
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_task.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="