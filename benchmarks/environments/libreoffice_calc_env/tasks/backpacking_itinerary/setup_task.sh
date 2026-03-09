#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Backpacking Itinerary Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create trail segment data CSV
cat > /home/ga/Documents/trail_segments.csv << 'EOF'
Day,Segment,Distance_Miles,Elevation_Gain_Ft
1,Trailhead to Bear Creek,3.5,800
1,Bear Creek to Meadow Camp,4.2,1200
2,Meadow Camp to Ridge Junction,5.1,1800
2,Ridge Junction to High Lake,3.8,900
3,High Lake to Summit Pass,6.5,3200
3,Summit Pass to Alpine Basin,4.2,600
4,Alpine Basin to Boulder Field,7.2,1500
4,Boulder Field to Crystal Lake,5.8,1200
4,Crystal Lake to Sunset Point,3.5,800
5,Sunset Point to Forest Glen,4.5,600
5,Forest Glen to River Camp,3.2,400
6,River Camp to Cliff Edge,6.8,2800
6,Cliff Edge to Valley View,4.1,700
7,Valley View to Parking Lot,5.5,600
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/trail_segments.csv
sudo chmod 644 /home/ga/Documents/trail_segments.csv

echo "✅ Created trail_segments.csv with 14 segments across 7 days"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/trail_segments.csv > /tmp/calc_itinerary.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_itinerary.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
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

# Move cursor to first empty column (column E) to prepare for adding columns
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right
sleep 0.3

echo "=== Backpacking Itinerary Task Setup Complete ==="
echo ""
echo "📋 TRIP PLANNING TASK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎒 Scenario: 7-day backpacking trip starting in 2 days"
echo "⚠️  Goal: Verify the itinerary is safe (no days exceed daylight hours)"
echo ""
echo "📝 Required Actions:"
echo "  1. Add column: 'Cumulative Distance (mi)' - running total of miles"
echo "  2. Add column: 'Est. Time (hours)' - formula: (Distance/2.5)+(Elevation/1000)"
echo "  3. Add column: 'Status' or use conditional formatting to flag problems:"
echo "     • Single segment > 6 hours: Warning"
echo "     • Elevation > 3000 ft: Steep"
echo "     • Daily total > 10 hours: Concerning"
echo "  4. Apply conditional formatting (optional): yellow=warning, red=danger"
echo ""
echo "💡 Hiking Time Estimation:"
echo "  • Base pace: ~2.5 mph on trails"
echo "  • Elevation penalty: ~1 hour per 1000 ft gain"
echo "  • Safe daylight: 10-12 hours maximum"
echo ""
echo "🎯 Expected Issues to Flag:"
echo "  • Day 3: Summit Pass climb (3200 ft elevation!)"
echo "  • Day 4: Very long day (~10 hours total)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"