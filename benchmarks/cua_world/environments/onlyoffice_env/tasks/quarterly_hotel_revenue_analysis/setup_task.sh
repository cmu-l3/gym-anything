#!/bin/bash
set -e

echo "=== Setting up Quarterly Hotel Revenue Analysis Task ==="

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
    cleanup_temp_files 2>/dev/null || true
    kill_onlyoffice ga 2>/dev/null || true
else
    pkill -f "onlyoffice-desktopeditors|DesktopEditors" 2>/dev/null || true
fi
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# ============================================================================
# Create deterministic, realistic PMS data
# ============================================================================
cat > /tmp/generate_hotel_data.py << 'PYEOF'
import csv
import random
from datetime import date, timedelta

random.seed(2024)

# Hotel Configuration
room_types = {
    "Standard King": {"count": 80, "rack_rate": 169},
    "Standard Double": {"count": 70, "rack_rate": 159},
    "Deluxe": {"count": 50, "rack_rate": 209},
    "Suite": {"count": 20, "rack_rate": 319}
}

rate_codes = {
    "BAR": {"discount": 0.95, "volatility": 0.1},
    "Corporate": {"discount": 0.75, "volatility": 0.05},
    "OTA": {"discount": 0.82, "volatility": 0.08},
    "Group": {"discount": 0.65, "volatility": 0.02},
    "Package": {"discount": 0.80, "volatility": 0.05}
}

# 1. Generate Room Inventory CSV
inventory_path = "/home/ga/Documents/Spreadsheets/room_inventory.csv"
with open(inventory_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["Room_Type", "Total_Rooms", "Rack_Rate"])
    for rt, data in room_types.items():
        writer.writerow([rt, data["count"], data["rack_rate"]])

# 2. Generate Daily Room Revenue CSV (Q3 2024: July 1 - Sept 30 = 92 days)
revenue_path = "/home/ga/Documents/Spreadsheets/daily_room_revenue.csv"
start_date = date(2024, 7, 1)

with open(revenue_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["Date", "Day_of_Week", "Room_Type", "Rate_Code", "Rooms_Sold", "Revenue"])
    
    for day_offset in range(92):
        current_date = start_date + timedelta(days=day_offset)
        dow = current_date.strftime("%A")
        
        # Seasonality adjustments
        month = current_date.month
        season_multiplier = 1.10 if month == 7 else (1.05 if month == 8 else 0.90)
        
        # Weekend vs Weekday adjustments
        is_weekend = dow in ["Friday", "Saturday"]
        leisure_mult = 1.25 if is_weekend else 0.85
        corp_mult = 0.60 if is_weekend else 1.15
        
        # Generate 5 records per day (one for each rate code) to get exactly 460 rows
        daily_rooms_sold = {rt: 0 for rt in room_types}
        
        for rc, rc_data in rate_codes.items():
            rt = random.choice(list(room_types.keys()))
            
            # Apply multipliers
            mult = leisure_mult if rc in ["BAR", "OTA", "Package"] else corp_mult
            target_occupancy = 0.70 * season_multiplier * mult * random.uniform(0.9, 1.1)
            
            # Ensure we don't overbook the hotel room type
            max_available = max(2, int((room_types[rt]["count"] - daily_rooms_sold[rt]) * 0.8))
            sold = min(max_available, int(room_types[rt]["count"] * target_occupancy / 5))
            sold = max(1, sold)
            daily_rooms_sold[rt] += sold
            
            # Calculate revenue
            effective_rate = room_types[rt]["rack_rate"] * rc_data["discount"] * random.uniform(1-rc_data["volatility"], 1+rc_data["volatility"])
            revenue = round(sold * effective_rate, 2)
            
            writer.writerow([current_date.strftime("%Y-%m-%d"), dow, rt, rc, sold, revenue])

PYEOF

python3 /tmp/generate_hotel_data.py
chown -R ga:ga "$WORKSPACE_DIR"

# ============================================================================
# Application Launch
# ============================================================================
echo "Starting ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:cell > /tmp/onlyoffice.log 2>&1 &"

# Wait for application window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "ONLYOFFICE"; then
        break
    fi
    sleep 1
done

# Maximize and Focus
DISPLAY=:1 wmctrl -r "ONLYOFFICE" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true

# Dismiss start dialogs if any
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="