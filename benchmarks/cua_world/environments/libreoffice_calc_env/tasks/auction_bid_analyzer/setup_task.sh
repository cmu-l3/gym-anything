#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Auction Bid Analyzer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with messy auction data
cat > /home/ga/Documents/auction_data.csv << 'EOF'
Item_ID,Item_Description,Category,Your_Bid,Winning_Bid,Outcome,Shipping_Cost,Max_Comfortable_Bid
A1001,Vintage Leica M3,Camera,450,475,LOST,,550
A1002,Rolex Submariner,watch,2100,2050,WON,25,2500
A1003,Canon AE-1 Program,camera,125,140,LOST,15,180
A1004,Omega Speedmaster,WATCH,1800,1850,LOST,,2000
A1002,Rolex Submariner,watch,2100,2050,WON,25,2500
A1005,Pentax K1000,Camera,95,95,WON,,120
A1006,Seiko 5 Sports,Watch,180,180,WON,12,200
A1007,Nikon F3,CAMERA,420,390,WON,30,450
A1008,Hasselblad 500C,camera,850,900,LOST,35,1000
A1009,Tissot PRX,watch,320,310,WON,8,400
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/auction_data.csv
sudo chmod 666 /home/ga/Documents/auction_data.csv

echo "✅ Created auction_data.csv with messy data (duplicates, inconsistent categories, missing shipping)"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/auction_data.csv > /tmp/calc_auction_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_auction_task.log || true
    # exit 1
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Ensure cursor is at beginning
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Auction Bid Analyzer Task Setup Complete ==="
echo "📊 Data Issues Present:"
echo "  - Inconsistent categories: 'Camera', 'camera', 'CAMERA', 'watch', 'Watch', 'WATCH'"
echo "  - Duplicate: Item A1002 appears twice"
echo "  - Missing shipping: Several items have blank shipping costs"
echo ""
echo "📝 Analysis Tasks:"
echo "  1. Standardize category names (all uppercase or lowercase)"
echo "  2. Remove duplicate Item_IDs (keep first occurrence)"
echo "  3. Create Total_Cost column: Your_Bid + Shipping_Cost (treat blank as 0)"
echo "  4. Calculate Win_Rate: (Count WON / Total bids) × 100"
echo "  5. Create Bid_Ratio column: Your_Bid / Max_Comfortable_Bid"
echo "  6. Flag items with Bid_Ratio >= 0.8 (emotional bidding)"
echo "  7. Calculate total spending: Sum Total_Cost for WON items only"
echo "  8. Save as auction_analysis.ods"