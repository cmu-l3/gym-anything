#!/bin/bash
# Do NOT use set -e to prevent premature exit
echo "=== Setting up meteorite_mass_analysis task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing agent files
rm -f /home/ga/Documents/meteorite_analyzer.py 2>/dev/null || true
rm -f /home/ga/Documents/top_10_meteorites.txt 2>/dev/null || true

# Generate the messy meteorite dataset
cat > /home/ga/Documents/meteorites.csv << 'EOF'
name,id,nametype,recclass,mass (g),fall,year,reclat,reclong,GeoLocation
Hoba,11890,Valid,Iron IVB,60000000,Found,1920,-19.58333,17.91667,"(-19.58333, 17.91667)"
Campo del Cielo,5247,Valid,Iron IAB-MG,50000000,Found,1576,-27.46667,-60.58333,"(-27.46667, -60.58333)"
Cape York,5262,Valid,Iron IIIAB,36200000,Found,1818,76.13333,-64.93333,"(76.13333, -64.93333)"
Willamette,24204,Valid,Iron IIIAB,15500000,Found,1902,45.36667,-122.58333,"(45.36667, -122.58333)"
Chupaderos,5363,Valid,Iron IIIAB,24300000,Found,1852,27,-105.1,"(27.0, -105.1)"
Mbozi,16456,Valid,Iron anomalous,25000000,Found,1930,-9.1,33,"(-9.1, 33.0)"
Armanty,2335,Valid,Iron IIIE,28000000,Found,1898,47,88,"(47.0, 88.0)"
Gibeon,10912,Valid,Iron IVA,26000000,Found,1836,-25.5,18,"(-25.5, 18.0)"
Sikhote-Alin,23593,Valid,Iron IIAB,23000000,Fell,1947,46.16,134.65333,"(46.16, 134.65333)"
Missing Mass Meteorite,99999,Valid,Stone,,Found,2000,0,0,"(0.0, 0.0)"
Bacubirito,4919,Valid,Iron,22000000,Found,1863,26.2,-107.83333,"(26.2, -107.83333)"
Another Missing,88888,Valid,Iron,,Found,2010,1,1,"(1.0, 1.0)"
Murnpeowie,16885,Valid,Iron,2520000,Found,1909,-29.58333,139.9,"(-29.58333, 139.9)"
Vaca Muerta,24146,Valid,Mesosiderite-A1,3830000,Found,1861,-25.66667,-70.5,"(-25.66667, -70.5)"
Canyon Diablo,5257,Valid,Iron IAB-MG,30000000,Found,1891,35.05,-111.03333,"(35.05, -111.03333)"
Aachen,1,Valid,L5,21,Fell,1880,50.775,6.08333,"(50.775, 6.08333)"
Aarhus,2,Valid,H6,720,Fell,1951,56.18333,10.23333,"(56.18333, 10.23333)"
Bad Data,77777,Valid,Stone,INVALID,Found,2020,0,0,"(0.0, 0.0)"
Abee,6,Valid,EH4,107000,Fell,1952,54.21667,-113,"(54.21667, -113.0)"
EOF
chown ga:ga /home/ga/Documents/meteorites.csv

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/meteorite_analysis_start_ts
chmod 666 /tmp/meteorite_analysis_start_ts

# Close any open activity to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Terminal activity to give the agent a workspace
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 5

# Verify Terminal is running
if pgrep -f "Terminal" > /dev/null 2>&1; then
    echo "Terminal activity is running"
else
    echo "WARNING: Terminal activity may not have started"
fi

# Take a verification screenshot of initial state
su - ga -c "$SUGAR_ENV scrot /tmp/meteorite_task_start.png" 2>/dev/null || true

echo "=== meteorite_mass_analysis task setup complete ==="
echo "Data is ready at /home/ga/Documents/meteorites.csv"
echo "Terminal is open for writing the Python script."