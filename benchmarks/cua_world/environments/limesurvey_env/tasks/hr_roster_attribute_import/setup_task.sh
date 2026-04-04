#!/bin/bash
set -e
echo "=== Setting up HR Roster Import Task ==="

source /workspace/scripts/task_utils.sh

# 1. Create the realistic CSV data file
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/employee_roster.csv << 'CSV'
firstname,lastname,email,department,location,manager_name
Sarah,Connor,s.connor@cyberdyne.com,R&D,San Francisco,Miles Dyson
John,Rambo,j.rambo@firstblood.com,Security,Hope,Sam Trautman
Ellen,Ripley,e.ripley@weyland.com,Logistics,Nostromo,Carter Burke
Dana,Scully,d.scully@fbi.gov,Science,Washington DC,Walter Skinner
Tony,Stark,t.stark@stark.com,Engineering,New York,Nick Fury
Bruce,Wayne,b.wayne@wayne.com,Management,Gotham,Lucius Fox
Diana,Prince,d.prince@themyscira.com,Diplomacy,Paris,Hippolyta
CSV

chown ga:ga /home/ga/Documents/employee_roster.csv
echo "Created /home/ga/Documents/employee_roster.csv"

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure Firefox is running and focused
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Wait for window and maximize
wait_for_window "Firefox" 20
focus_firefox
maximize_window "Firefox"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="