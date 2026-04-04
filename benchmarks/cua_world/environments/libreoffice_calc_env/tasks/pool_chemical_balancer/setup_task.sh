#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Pool Chemical Balancer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy pool test results CSV
cat > /home/ga/Documents/pool_test_results.csv << 'EOF'
Parameter,Current Reading,Unit,Test Notes
pH,7.9 (slightly high),unitless,Above target range
Free Chlorine,0.3,ppm,CRITICAL - dangerously low!
Total Alkalinity,60 ppm,ppm,Below recommended
Calcium Hardness,180,ppm,Acceptable but low
Cyanuric Acid,35,ppm,OK
Water Temperature,78,F,Good for swimming
Total Chlorine,0.35,ppm,Includes combined chlorine
Combined Chlorine,0.05,ppm,Within limits
Phosphates,150,ppb,Moderate level
EOF

chown ga:ga /home/ga/Documents/pool_test_results.csv
chmod 644 /home/ga/Documents/pool_test_results.csv

# Create chemical dosing reference table CSV
cat > /home/ga/Documents/chemical_dosing_reference.csv << 'EOF'
Chemical,Unit,Price_per_Unit,Standard_Divisor,Notes
Muriatic Acid (31%),oz,0.12,10000,For lowering pH
Soda Ash,lb,1.80,10000,For raising pH
Liquid Chlorine (12%),lb,3.50,75000,Temperature dependent
Baking Soda,lb,1.20,150000,For alkalinity
Calcium Chloride,lb,2.50,120000,For hardness

Temperature Correction Factors
Temperature_F,Chlorine_Factor
70,0.9
75,1.0
78,1.1
80,1.2
85,1.3

Target Ranges
Parameter,Min_Target,Max_Target,Ideal
pH,7.2,7.6,7.4
Free Chlorine,1.0,3.0,2.0
Total Alkalinity,80,120,100
Calcium Hardness,200,400,250
EOF

chown ga:ga /home/ga/Documents/chemical_dosing_reference.csv
chmod 644 /home/ga/Documents/chemical_dosing_reference.csv

echo "✅ Created pool_test_results.csv with messy data"
echo "✅ Created chemical_dosing_reference.csv with lookup tables"

# Launch LibreOffice Calc with the test results CSV
echo "Launching LibreOffice Calc with pool test results..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/pool_test_results.csv > /tmp/calc_pool_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_pool_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
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

echo "=== Pool Chemical Balancer Task Setup Complete ==="
echo ""
echo "🏊 SCENARIO: Memorial Day weekend pool opening - chemicals need balancing TODAY"
echo ""
echo "📋 Files created:"
echo "   • pool_test_results.csv (messy data with text notes and typos)"
echo "   • chemical_dosing_reference.csv (lookup tables for calculations)"
echo ""
echo "🎯 Your mission:"
echo "   1. Clean the messy test data (remove text, standardize units)"
echo "   2. Calculate chemical adjustments for 25,000-gallon pool"
echo "   3. Apply proper dosing formulas (pH, chlorine, alkalinity, calcium)"
echo "   4. Flag urgency levels (CRITICAL/URGENT/ROUTINE)"
echo "   5. Calculate total cost vs. $400 professional quote"
echo ""
echo "⚗️  Expected calculations:"
echo "   • Acid: ~20 oz (pH 7.9 → 7.4)"
echo "   • Chlorine: ~0.62 lbs (0.3 → 2.0 ppm, temp-corrected)"
echo "   • Baking Soda: ~6.67 lbs (alkalinity 60 → 100 ppm)"
echo "   • Calcium: ~14.58 lbs (hardness 180 → 250 ppm)"
echo ""
echo "💡 Remember: Fix pH BEFORE chlorine (pH affects chlorine effectiveness)!"