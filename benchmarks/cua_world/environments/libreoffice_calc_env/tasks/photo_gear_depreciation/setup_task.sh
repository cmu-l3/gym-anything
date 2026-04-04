#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Photography Gear Depreciation Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy photography gear CSV with inconsistent formats
cat > /home/ga/Documents/photography_gear_messy.csv << 'CSVEOF'
Item Name,Category,Purchase Date,Purchase Price,Current Market Value
Canon EOS R5,Camera Body,2021-03-15,3899.00,2800
Sony A7 IV,Camera Body,March 2022,2498,2200
Canon EF 24-70mm f/2.8,Lens,2019-08-22,1799.00,1200
Godox AD600 Pro,Accessory,Jan 2020,,450
MacBook Pro 16",Computer/Storage,2020-11-03,2799.00,1600
Canon RF 70-200mm f/2.8,Lens,2021-12-10,2899.00,2400
Manfrotto MT055CXPRO3,Accessory,2018-05-15,249.99,80
SanDisk 1TB Extreme SSD,Computer/Storage,Feb 2023,179.00,140
Canon EF 50mm f/1.8 STM,Lens,2017-04-20,125.00,100
Neewer LED Panel 660,Accessory,November 2019,89.99,40
Sony FE 85mm f/1.8,Lens,2020-07-08,598.00,450
DJI Ronin-S Gimbal,Accessory,Sep 2021,349.00,200
Tamron 28-75mm f/2.8,Lens,01/15/2022,879.00,750
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/photography_gear_messy.csv
sudo chmod 666 /home/ga/Documents/photography_gear_messy.csv

echo "✅ Created photography_gear_messy.csv with intentional data quality issues"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/photography_gear_messy.csv > /tmp/calc_depreciation_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_depreciation_task.log
    # exit 1
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Photography Gear Depreciation Task Setup Complete ==="
echo ""
echo "📸 SCENARIO: You're a professional photographer preparing year-end taxes"
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "  Your gear inventory spreadsheet has data quality issues that need fixing:"
echo ""
echo "  STEP 1 - DATA CLEANUP:"
echo "    • Standardize all Purchase Dates to consistent format (YYYY-MM-DD or DD/MM/YYYY)"
echo "    • Fill missing Purchase Prices with reasonable estimates (Godox AD600 Pro ~$900)"
echo ""
echo "  STEP 2 - CALCULATE DEPRECIATION:"
echo "    Add these columns with formulas:"
echo "    • Years Owned: Calculate age using TODAY() and Purchase Date"
echo "    • Useful Life (Years): IF formula based on Category:"
echo "      - Camera Body → 5 years"
echo "      - Lens → 7 years"
echo "      - Accessory → 3 years"
echo "      - Computer/Storage → 3 years"
echo "    • Annual Depreciation: Purchase Price / Useful Life"
echo "    • Accumulated Depreciation: Annual Depreciation × MIN(Years Owned, Useful Life)"
echo "    • Book Value: Purchase Price - Accumulated Depreciation (minimum 0)"
echo ""
echo "  STEP 3 - IDENTIFY OPPORTUNITIES:"
echo "    • Sell?: IF(Market Value > Book Value, \"YES\", \"NO\")"
echo "    • Total Depreciation (Current Year): SUM of annual depreciation for non-fully-depreciated items"
echo ""
echo "💡 HINTS:"
echo "  - Use DATEDIF, YEARFRAC, or (TODAY()-Date)/365.25 for age calculations"
echo "  - Use nested IF statements for category-based useful life"
echo "  - Use MAX(0, calculation) to prevent negative book values"
echo "  - Formula for accumulated: =Annual_Dep * MIN(Years_Owned, Useful_Life)"
echo ""
echo "🎯 SUCCESS CRITERIA:"
echo "  ✓ All dates standardized to valid date format"
echo "  ✓ No missing purchase prices"
echo "  ✓ Formulas (not hardcoded values) for all calculations"
echo "  ✓ Correct depreciation logic by equipment category"
echo "  ✓ Sell candidates identified where market > book value"
echo ""