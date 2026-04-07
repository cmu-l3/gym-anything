#!/bin/bash
echo "=== Setting up Mauna Loa CO2 Analysis Task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing output files
rm -f /home/ga/Documents/analyze_co2.py 2>/dev/null || true
rm -f /home/ga/Documents/co2_report.html 2>/dev/null || true

# Write the authentic NOAA Mauna Loa CO2 dataset
cat > /home/ga/Documents/co2_data.csv << 'CSVEOF'
year,mean
1979,336.84
1980,338.76
1981,340.12
1982,341.48
1983,343.15
1984,344.85
1985,346.04
1986,347.39
1987,349.16
1988,351.56
1989,353.07
1990,354.35
1991,355.57
1992,356.38
1993,357.07
1994,358.82
1995,360.80
1996,362.59
1997,363.71
1998,366.65
1999,368.33
2000,369.52
2001,371.13
2002,373.22
2003,375.77
2004,377.49
2005,379.80
2006,381.90
2007,383.77
2008,385.59
2009,387.38
2010,389.85
2011,391.63
2012,393.82
2013,396.48
2014,398.61
2015,400.83
2016,404.24
2017,406.55
2018,408.52
2019,411.44
CSVEOF
chown ga:ga /home/ga/Documents/co2_data.csv

# Record task start timestamp
date +%s > /tmp/co2_task_start_ts
chmod 666 /tmp/co2_task_start_ts

# Close any open activities to return to the Sugar home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Take an initial screenshot to prove starting state
su - ga -c "$SUGAR_ENV scrot /tmp/co2_task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="
echo "co2_data.csv is ready in /home/ga/Documents/"