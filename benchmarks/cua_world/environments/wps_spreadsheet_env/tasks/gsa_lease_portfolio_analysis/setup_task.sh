#!/bin/bash
set -e
echo "=== Setting up GSA Lease Portfolio Analysis Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create realistic GSA lease dataset (based on real FOIA lease structures)
cat << 'EOF' > /home/ga/Documents/gsa_leases.csv
Lease_Number,City,State,Tenant_Agency,Lease_Start_Date,Lease_End_Date,Rentable_Sq_Ft,Annual_Rent
GS-03P-LMD121,Baltimore,MD,Social Security Admin,2015-01-01,2024-12-31,15000,450000
GS-11P-LVA543,Arlington,VA,Dept of Defense,2018-05-01,2027-04-30,25000,1125000
GS-11P-LDC987,Washington,DC,Dept of Justice,2020-10-01,2030-09-30,50000,2500000
GS-09P-LCA111,Los Angeles,CA,Dept of Homeland Security,2016-02-01,2026-01-31,12000,600000
GS-07P-LTX222,Dallas,TX,Federal Bureau of Investigation,2014-06-01,2024-05-31,18000,720000
GS-03P-LMD122,Bethesda,MD,National Institutes of Health,2021-01-01,2031-12-31,30000,1500000
GS-11P-LDC102,Washington,DC,Dept of Energy,2017-03-01,2027-02-28,40000,1800000
GS-09P-LCA333,San Francisco,CA,Environmental Protection Agency,2015-08-01,2025-07-31,22000,1210000
GS-07P-LTX444,Austin,TX,Internal Revenue Service,2019-11-01,2029-10-31,28000,980000
GS-11P-LVA555,Alexandria,VA,National Science Foundation,2016-09-01,2026-08-31,60000,2400000
GS-11P-LDC999,Washington,DC,Dept of State,2013-01-01,2025-12-31,85000,4250000
GS-03P-LMD444,Rockville,MD,Food and Drug Admin,2018-04-01,2028-03-31,35000,1575000
GS-07P-LTX888,Houston,TX,Coast Guard,2022-02-01,2032-01-31,15000,525000
GS-09P-LCA777,San Diego,CA,Customs and Border Protection,2020-07-01,2025-06-30,20000,900000
GS-11P-LVA222,Falls Church,VA,Defense Health Agency,2019-01-01,2029-12-31,45000,1890000
EOF

# Ensure proper permissions
chown ga:ga /home/ga/Documents/gsa_leases.csv

# Ensure application is running
if ! pgrep -x "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et /home/ga/Documents/gsa_leases.csv &"
    sleep 5
fi

# Wait for window to appear
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -i "WPS Spreadsheets\|gsa_leases"; then
        break
    fi
    sleep 1
done

# Maximize window for agent visibility
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a :ACTIVE: 2>/dev/null || true

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state (for evidence)
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="