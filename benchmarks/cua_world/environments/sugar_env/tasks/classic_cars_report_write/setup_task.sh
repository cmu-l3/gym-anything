#!/bin/bash
echo "=== Setting up classic_cars_report_write task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents

# Remove any pre-existing report file
rm -f /home/ga/Documents/classic_cars_report.odt 2>/dev/null || true

# Download the real mpg dataset from seaborn-data
echo "Downloading mpg.csv dataset..."
wget -q "https://raw.githubusercontent.com/mwaskom/seaborn-data/master/mpg.csv" -O /home/ga/Documents/mpg.csv

# Fallback dataset if download fails (to guarantee offline robustness)
if [ ! -s /home/ga/Documents/mpg.csv ]; then
    echo "Download failed. Creating fallback dataset..."
    cat << 'EOF' > /home/ga/Documents/mpg.csv
mpg,cylinders,displacement,horsepower,weight,acceleration,model_year,origin,name
18.0,8,307.0,130.0,3504,12.0,70,usa,chevrolet chevelle malibu
15.0,8,350.0,165.0,3693,11.5,70,usa,buick skylark 320
18.0,8,318.0,150.0,3436,11.0,70,usa,plymouth satellite
16.0,8,304.0,150.0,3433,12.0,70,usa,amc rebel sst
17.0,8,302.0,140.0,3449,10.5,70,usa,ford torino
15.0,8,429.0,198.0,4341,10.0,70,usa,ford galaxie 500
14.0,8,454.0,220.0,4354,9.0,70,usa,chevrolet impala
14.0,8,440.0,215.0,4312,8.5,70,usa,plymouth fury iii
14.0,8,455.0,225.0,4425,10.0,70,usa,pontiac catalina
15.0,8,390.0,190.0,3850,8.5,70,usa,amc ambassador dpl
46.6,4,86.0,65.0,2110,17.9,80,japan,mazda glc
35.0,4,122.0,88.0,2500,15.1,80,europe,triumph tr7 coupe
40.8,4,85.0,65.0,2110,19.2,80,japan,datsun 210
44.3,4,90.0,48.0,2085,21.7,80,europe,vw rabbit c (diesel)
43.4,4,90.0,48.0,2335,23.7,80,europe,vw dasher (diesel)
31.0,4,119.0,82.0,2720,19.4,82,usa,chevy s-10
24.0,4,113.0,95.0,2372,15.0,70,japan,toyota corona mark ii
20.0,6,198.0,95.0,3102,16.5,74,usa,plymouth duster
21.0,6,200.0,?,2875,17.0,74,usa,ford maverick
EOF
fi

chown ga:ga /home/ga/Documents/mpg.csv

# Record task start timestamp for mtime validation
date +%s > /tmp/classic_cars_start_ts
chmod 666 /tmp/classic_cars_start_ts

# Close any open activities first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Take a verification screenshot of the start state
su - ga -c "$SUGAR_ENV scrot /tmp/task_start.png" 2>/dev/null || true

echo "=== classic_cars_report_write task setup complete ==="
echo "Dataset downloaded to /home/ga/Documents/mpg.csv"
echo "Waiting for agent to analyze data and create Write document."