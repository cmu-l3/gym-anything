#!/bin/bash
echo "=== Setting up hurricane_fiona_buoy_analysis task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any artifacts from previous runs
rm -f /home/ga/Documents/analyze_hurricane.*
rm -f /home/ga/Documents/hurricane_summary.txt

# Download real NOAA dataset
echo "Downloading NOAA Buoy 41046 data..."
wget -q -T 30 "https://www.ndbc.noaa.gov/data/historical/stdmet/41046h2022.txt.gz" -O /tmp/41046h2022.txt.gz || true

if [ -s "/tmp/41046h2022.txt.gz" ]; then
    echo "Download successful, extracting..."
    gunzip -c /tmp/41046h2022.txt.gz > /home/ga/Documents/buoy_41046_2022.txt
else
    echo "Download failed, using realistic mock data..."
    # Fallback to realistic mock data snippet if download fails
    cat > /home/ga/Documents/buoy_41046_2022.txt << 'EOF'
#YY  MM DD hh mm WDIR WSPD GST  WVHT   DPD   APD MWD   PRES  ATMP  WTMP  DEWP  VIS PTDY  TIDE
#yr  mo dy hr mn degT m/s  m/s     m   sec   sec degT   hPa  degC  degC  degC  nmi hPa    ft
2022 08 31 23 50  120  5.0  6.5  1.20  5.00  4.00 130 1012.0  28.5  29.0 999.0 99.0 +0.0 99.0
2022 09 01 00 50  125  5.5  7.0  1.25  5.00  4.00 130 1011.5  28.5  29.0 999.0 99.0 -0.5 99.0
2022 09 18 12 50   90 15.0 20.0  5.50  8.00  6.00  90  995.0  27.0  28.5 999.0 99.0 -3.0 99.0
2022 09 19 00 50   80 25.0 35.0 12.50 12.00  9.00  80  945.5  26.0  28.0 999.0 99.0 -5.0 99.0
2022 09 19 01 50   70 28.0 38.0 15.60 14.00 10.00  70  932.1  25.5  28.0 999.0 99.0 -8.0 99.0
2022 09 19 02 50  999 99.0 99.0 99.00 99.00 99.00 999 9999.0 999.0 999.0 999.0 99.0 99.0 99.0
2022 09 20 00 50  300 12.0 16.0  4.50  7.00  5.00 300 1005.0  27.5  28.5 999.0 99.0 +2.0 99.0
2022 10 01 00 50  150  6.0  8.0  1.40  5.00  4.00 150 1014.0  28.0  28.5 999.0 99.0 +1.0 99.0
EOF
fi

chown ga:ga /home/ga/Documents/buoy_41046_2022.txt

# Record task start timestamp for verification
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Close any open activities first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Open Sugar Terminal Activity
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 5

# Optional: Fullscreen Terminal for better visibility
su - ga -c "$SUGAR_ENV xdotool key alt+Enter" 2>/dev/null || true
sleep 1

# Capture initial state screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="