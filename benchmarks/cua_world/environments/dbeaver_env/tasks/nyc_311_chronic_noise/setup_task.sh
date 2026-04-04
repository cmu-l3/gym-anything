#!/bin/bash
set -e
echo "=== Setting up NYC 311 Chronic Noise Analysis Task ==="

source /workspace/scripts/task_utils.sh

DATA_DIR="/home/ga/Documents/data"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"
CSV_FILE="$DATA_DIR/nyc_noise.csv"

# Ensure directories exist
mkdir -p "$DATA_DIR" "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents

# 1. Acquire Data (Real NYC 311 Data)
# We will download a specific slice of data to ensure the task is deterministic yet real.
# If download fails, we fall back to a smaller cached/synthetic set for robustness,
# but the primary goal is real data.
# URL is a query to NYC Open Data Socrata API for Noise - Residential in a specific month (e.g., Oct 2023)
echo "Acquiring 311 data..."

if [ ! -f "$CSV_FILE" ]; then
    # Download ~2000 rows of real data
    # Query: SELECT * WHERE complaint_type='Noise - Residential' AND created_date between '2023-10-01' and '2023-11-01' LIMIT 2000
    URL="https://data.cityofnewyork.us/resource/erm2-nwe9.csv?\$where=complaint_type='Noise%20-%20Residential'%20AND%20created_date%20between%20'2023-10-01T00:00:00'%20AND%20'2023-11-01T23:59:59'&\$limit=3000&\$order=created_date"
    
    wget --timeout=30 -O "$CSV_FILE" "$URL" 2>/dev/null || true
    
    # Check if download succeeded and has content
    if [ ! -s "$CSV_FILE" ]; then
        echo "WARNING: Download failed. Generating fallback data based on real patterns..."
        cat > "$CSV_FILE" << EOF
Unique Key,Created Date,Complaint Type,Incident Address,Borough
1001,10/01/2023 11:00:00 PM,Noise - Residential,123 MAIN ST,MANHATTAN
1002,10/02/2023 10:00:00 PM,Noise - Residential,123 MAIN ST,MANHATTAN
1003,10/03/2023 11:30:00 PM,Noise - Residential,123 MAIN ST,MANHATTAN
1004,10/01/2023 09:00:00 AM,Noise - Residential,456 BROADWAY,MANHATTAN
1005,10/05/2023 09:00:00 AM,Noise - Residential,456 BROADWAY,MANHATTAN
1006,10/10/2023 09:00:00 AM,Noise - Residential,456 BROADWAY,MANHATTAN
1007,10/01/2023 01:00:00 AM,Noise - Residential,789 5TH AVE,MANHATTAN
1008,10/01/2023 02:00:00 AM,Noise - Residential,789 5TH AVE,MANHATTAN
1009,10/15/2023 03:00:00 AM,Noise - Residential,789 5TH AVE,MANHATTAN
EOF
        # Note: 123 MAIN ST is chronic (3 in 3 days). 
        # 456 BROADWAY is NOT chronic (3 complaints but spread > 7 days: 1st, 5th, 10th - span is 9 days).
        # 789 5TH AVE is NOT chronic (3 complaints but dates are 1st, 1st, 15th - span is 14 days).
    fi
fi

# Set permissions
chown ga:ga "$CSV_FILE"
echo "Data ready at $CSV_FILE"

# 2. Start DBeaver
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    # Wait for DBeaver to start
    for i in {1..30}; do
        if is_dbeaver_running; then
            echo "DBeaver started."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 3. Record initial state
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_script_size.txt

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="