#!/bin/bash
echo "=== Setting up field_trip_gps_kml_converter task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any old files
rm -f /home/ga/Documents/route.kml 2>/dev/null || true
rm -f /home/ga/Documents/kml_generator.py 2>/dev/null || true
rm -f /home/ga/Documents/kml_generator.sh 2>/dev/null || true

# Generate the GPS CSV file with realistic data (Inca Trail)
cat > /home/ga/Documents/inca_trail_track.csv << 'EOF'
Time,Latitude,Longitude,Elevation
2023-10-14T10:00:00Z,-13.226333,-72.497500,2800.0
2023-10-14T10:05:00Z,-13.225500,-72.498833,2815.5
2023-10-14T10:10:00Z,-13.224167,-72.500500,2830.2
2023-10-14T10:15:00Z,-13.222833,-72.502167,2850.8
2023-10-14T10:20:00Z,-13.221500,-72.503833,2875.0
2023-10-14T10:25:00Z,-13.220167,-72.505500,2890.3
2023-10-14T10:30:00Z,-13.218833,-72.507167,2910.1
2023-10-14T10:35:00Z,-13.217500,-72.508833,2925.6
2023-10-14T10:40:00Z,-13.216167,-72.510500,2940.4
2023-10-14T10:45:00Z,-13.214833,-72.512167,2955.9
2023-10-14T10:50:00Z,-13.213500,-72.513833,2970.2
2023-10-14T10:55:00Z,-13.212167,-72.515500,2990.5
2023-10-14T11:00:00Z,-13.210833,-72.517167,3010.8
2023-10-14T11:05:00Z,-13.209500,-72.518833,3030.1
2023-10-14T11:10:00Z,-13.208167,-72.520500,3045.4
2023-10-14T11:15:00Z,-13.206833,-72.522167,3060.7
2023-10-14T11:20:00Z,-13.205500,-72.523833,3075.2
2023-10-14T11:25:00Z,-13.204167,-72.525500,3090.5
2023-10-14T11:30:00Z,-13.202833,-72.527167,3110.3
2023-10-14T11:35:00Z,-13.201500,-72.528833,3125.8
EOF
chown ga:ga /home/ga/Documents/inca_trail_track.csv

# Record start time
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Return to Sugar Home
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 2

# Verify Sugar is running
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Launch Terminal automatically to save some time
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 5

# Take initial screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Task setup complete ==="