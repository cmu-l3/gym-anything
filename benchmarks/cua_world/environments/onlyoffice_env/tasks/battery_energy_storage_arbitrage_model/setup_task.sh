#!/bin/bash
set -euo pipefail

echo "=== Setting up Battery Energy Storage Arbitrage Model Task ==="

# Record task start time
echo $(date +%s) > /tmp/task_start_time.txt

# Load ONLYOFFICE utilities
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Clean up any existing instances and files
pkill -f "onlyoffice-desktopeditors|DesktopEditors" 2>/dev/null || true
rm -f /tmp/bess_*.json 2>/dev/null || true
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
CSV_PATH="$WORKSPACE_DIR/caiso_sp15_2023_8760.csv"

# Generate the 8760 CAISO data file using a python script
# This simulates real CAISO pricing phenomena (duck curve, evening peaks, negative daytime prices)
cat > /tmp/generate_caiso_data.py << 'PYEOF'
import csv
import random
from datetime import datetime, timedelta

# Set seed for deterministic pricing data
random.seed(2023)

start_date = datetime(2023, 1, 1)
output_path = "/home/ga/Documents/Spreadsheets/caiso_sp15_2023_8760.csv"

with open(output_path, "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["Date", "Hour", "LMP"])
    
    for day in range(365):
        current_date = start_date + timedelta(days=day)
        date_str = current_date.strftime("%Y-%m-%d")
        
        # Seasonality factors
        month = current_date.month
        is_summer = 6 <= month <= 9
        is_spring = 3 <= month <= 5
        
        daily_volatility = random.uniform(0.5, 2.0)
        
        for hour in range(1, 25):
            # Base price
            price = 35 + random.uniform(-10, 15)
            
            # Morning peak (Hours 6-9)
            if 6 <= hour <= 9:
                price += 15 * daily_volatility
                
            # Midday solar generation / Duck Curve (Hours 10-16)
            elif 10 <= hour <= 16:
                if is_spring:
                    # High solar, low demand = negative prices
                    price -= random.uniform(40, 60)
                else:
                    price -= random.uniform(10, 30)
                    
            # Evening net-peak (Hours 17-21)
            elif 17 <= hour <= 21:
                if is_summer:
                    # Extreme summer scarcity pricing
                    price += random.uniform(100, 350) * daily_volatility
                else:
                    price += random.uniform(40, 80) * daily_volatility
            
            # Add some random noise
            price += random.uniform(-5, 5)
            
            writer.writerow([date_str, hour, round(price, 2)])
PYEOF

echo "Generating 8760 hourly price dataset..."
python3 /tmp/generate_caiso_data.py
chown ga:ga "$CSV_PATH"

# Launch ONLYOFFICE with the CSV file
echo "Starting ONLYOFFICE..."
sudo -u ga DISPLAY=:1 onlyoffice-desktopeditors "$CSV_PATH" > /tmp/onlyoffice_launch.log 2>&1 &

# Wait for the application window to appear
echo "Waiting for ONLYOFFICE window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "onlyoffice\|Desktop Editors"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Allow time for the UI and document to fully render
sleep 4

# Maximize and focus the window
echo "Maximizing ONLYOFFICE window..."
WID=$(DISPLAY=:1 wmctrl -l | grep -i 'onlyoffice\|Desktop Editors' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="