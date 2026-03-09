#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Plant Propagation Success Analyzer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy propagation data CSV with realistic informal entries
cat > /home/ga/Documents/propagation_log.csv << 'EOF'
Date Started,Plant Type,Method,Date Rooted,Outcome,Notes
March 15,Pothos,water,March 28,roots!,so fast!
3/18/23,Monstera,soil,,rotted,too wet maybe
mid-March,String of Pearls,perlite,4/2/23,success,took forever
2023-03-20,Philodendron,water,March 29,rooted,gave to mom
3/22,Snake Plant,water,,still waiting,no progress yet
March 25,Pothos,LECA,Apr 5,planted in soil,worked great
3/28/23,Monstera,water,4/15/23,roots,slow but worked
April 1,ZZ Plant,soil,,dead,rotted at base
4/3/2023,Pothos,water,April 14,success!,beautiful roots
Apr 5,Spider Plant,perlite,4/18/23,rooted,gave to neighbor
mid-April,String of Pearls,water,,gave up,no roots after 8 weeks
2023-04-10,Philodendron,soil,Apr 28,planted,good roots
4/12,Monstera,sphagnum,May 2,roots!,first time trying sphagnum
April 15,Pothos,soil,5/5/23,success,slower than water
4/18/23,Snake Plant,perlite,,rotted,overwatered
Apr 20,Spider Plant,water,May 1,rooted,fast
2023-04-22,ZZ Plant,perlite,5/15/23,planted,finally worked
4/25,Philodendron,water,May 6,roots,consistent
May 1,Pothos,water,May 12,success!,always reliable
5/3/2023,String of Pearls,soil,,dead,rot again
mid-May,Monstera,LECA,6/1/23,rooted,LECA is great
2023-05-08,Spider Plant,water,May 18,success,gave away
5/10,ZZ Plant,water,,still waiting,very slow
May 12,Pothos,perlite,5/28/23,planted,perlite works too
5/15/23,Philodendron,sphagnum,May 30,rooted,good method
5/18,Snake Plant,soil,,rotted,soil too dense
May 20,Monstera,water,6/5/23,roots,reliable
5/22/2023,String of Pearls,perlite,,gave up,no luck with this plant
5/25,Pothos,water,June 3,success!,pothos always works
June 1,Spider Plant,soil,6/20/23,planted,soil worked
6/3/2023,ZZ Plant,perlite,6/28/23,rooted,patience needed
Jun 5,Philodendron,water,June 15,roots,fast rooting
2023-06-08,Monstera,perlite,6/25/23,success,good combo
6/10,Pothos,LECA,6/22/23,rooted,LECA is reliable
mid-June,Snake Plant,water,,still waiting,month 2
June 15,String of Pearls,water,,dead,just doesn't work for me
6/18/23,Spider Plant,water,June 28,success,quick roots
Jun 20,Pothos,soil,7/10/23,planted,slower but works
2023-06-22,Philodendron,perlite,7/5/23,rooted,consistent results
6/25,Monstera,water,July 8,roots,always reliable
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/propagation_log.csv
sudo chmod 644 /home/ga/Documents/propagation_log.csv

echo "✅ Created propagation_log.csv with 40 entries"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/propagation_log.csv > /tmp/calc_propagation_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_propagation_task.log || true
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

# Position cursor at beginning
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Plant Propagation Success Analyzer Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Clean up inconsistent date formats (create helper columns if needed)"
echo "  2. Determine success/failure from outcome descriptions"
echo "  3. Calculate rooting duration for successful propagations"
echo "  4. Calculate success rate by propagation method"
echo "  5. Calculate success rate by plant type"
echo "  6. Calculate average rooting times"
echo "  7. Create summary table(s) with insights"
echo "  8. Apply conditional formatting to highlight patterns"