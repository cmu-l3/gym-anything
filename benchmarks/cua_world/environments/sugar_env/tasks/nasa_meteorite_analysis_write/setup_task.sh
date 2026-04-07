#!/bin/bash
echo "=== Setting up nasa_meteorite_analysis_write task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove pre-existing file to ensure a clean slate
rm -f /home/ga/Documents/heaviest_meteorites.odt 2>/dev/null || true

# Prepare the meteorite dataset
echo "Downloading meteorite dataset..."
if ! wget -q --timeout=10 -O /home/ga/Documents/meteorite_landings.csv "https://data.nasa.gov/api/views/gh4g-9sfh/rows.csv?accessType=DOWNLOAD"; then
    echo "Download failed or timed out. Using real fallback subset..."
    cat > /home/ga/Documents/meteorite_landings.csv << 'EOF'
name,id,nametype,recclass,mass (g),fall,year,reclat,reclong,GeoLocation
Aachen,1,Valid,L5,21,Fell,01/01/1880 12:00:00 AM,50.77500,6.08333,"(50.775000, 6.083330)"
Aarhus,2,Valid,H6,720,Fell,01/01/1951 12:00:00 AM,56.18333,10.23333,"(56.183330, 10.233330)"
Campo del Cielo,5247,Valid,Iron IAB-MG,50000000,Found,01/01/1576 12:00:00 AM,-27.46667,-60.58333,"(-27.466670, -60.583330)"
Abee,6,Valid,EH4,107000,Fell,01/01/1952 12:00:00 AM,54.21667,-113.00000,"(54.216670, -113.000000)"
Hoba,11890,Valid,Iron IVB,60000000,Found,01/01/1920 12:00:00 AM,-19.58333,17.91667,"(-19.583330, 17.916670)"
Acapulco,10,Valid,Acapulcoite,1914,Fell,01/01/1976 12:00:00 AM,16.88333,-99.90000,"(16.883330, -99.900000)"
Cape York,5262,Valid,Iron IIIAB,36200000,Found,01/01/1818 12:00:00 AM,76.13333,-64.93333,"(76.133330, -64.933330)"
Achiras,370,Valid,L6,780,Fell,01/01/1902 12:00:00 AM,-33.16667,-64.95000,"(-33.166670, -64.950000)"
Canyon Diablo,5257,Valid,Iron IAB-MG,30000000,Found,01/01/1891 12:00:00 AM,35.05000,-111.03333,"(35.050000, -111.033330)"
Adhi Kot,379,Valid,EH4,4239,Fell,01/01/1919 12:00:00 AM,32.10000,71.80000,"(32.100000, 71.800000)"
Willamette,24288,Valid,Iron IIIAB,15500000,Found,01/01/1902 12:00:00 AM,45.36667,-122.58333,"(45.366670, -122.583330)"
Adzhi-Bogdo (stone),390,Valid,LL3-6,910,Fell,01/01/1949 12:00:00 AM,44.83333,95.16667,"(44.833330, 95.166670)"
Agen,392,Valid,H5,30000,Fell,01/01/1814 12:00:00 AM,44.21667,0.61667,"(44.216670, 0.616670)"
Aguada,398,Valid,L6,1620,Fell,01/01/1930 12:00:00 AM,-31.60000,-65.23333,"(-31.600000, -65.233330)"
Aguila Blanca,417,Valid,L,1440,Fell,01/01/1920 12:00:00 AM,-30.86667,-64.55000,"(-30.866670, -64.550000)"
EOF
fi
chown ga:ga /home/ga/Documents/meteorite_landings.csv

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/meteorite_task_start_ts
chmod 666 /tmp/meteorite_task_start_ts

# Close any open activities to return to the Home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Ensure Sugar session is active
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, restarting..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take verification screenshot of the starting state
su - ga -c "$SUGAR_ENV scrot /tmp/meteorite_task_start.png" 2>/dev/null || true

echo "=== nasa_meteorite_analysis_write task setup complete ==="