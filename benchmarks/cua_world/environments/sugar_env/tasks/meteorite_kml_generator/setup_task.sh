#!/bin/bash
echo "=== Setting up meteorite_kml_generator task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp
date +%s > /tmp/meteorite_kml_start_ts
chmod 666 /tmp/meteorite_kml_start_ts

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous files
rm -f /home/ga/Documents/generate_kml.py 2>/dev/null || true
rm -f /home/ga/Documents/massive_meteorites.kml 2>/dev/null || true

# Generate realistic NASA Meteorite Landings CSV subset
cat > /home/ga/Documents/meteorite_landings.csv << 'EOF'
name,id,nametype,recclass,mass (g),fall,year,reclat,reclong,GeoLocation
Aachen,1,Valid,L5,21,Fell,01/01/1880 12:00:00 AM,50.775000,6.083330,"(50.775000, 6.083330)"
Abee,3,Valid,EH4,107000,Fell,01/01/1952 12:00:00 AM,54.166670,-113.000000,"(54.166670, -113.000000)"
Allende,7,Valid,CV3,2000000,Fell,01/01/1969 12:00:00 AM,26.966670,-105.316670,"(26.966670, -105.316670)"
Campo del Cielo,5,Valid,IAB-MG,50000000,Found,01/01/1576 12:00:00 AM,-27.466670,-60.583330,"(-27.466670, -60.583330)"
Chelyabinsk,9,Valid,LL5,100000,Fell,01/01/2013 12:00:00 AM,54.816670,60.116670,"(54.816670, 60.116670)"
Gibeon,4,Valid,IVA,26000000,Found,01/01/1836 12:00:00 AM,-25.500000,17.750000,"(-25.500000, 17.750000)"
Jilin,8,Valid,H5,4000000,Fell,01/01/1976 12:00:00 AM,44.050000,126.320000,"(44.050000, 126.320000)"
Sikhote-Alin,6,Valid,IIAB,23000000,Fell,01/01/1947 12:00:00 AM,46.160000,-134.653330,"(46.160000, -134.653330)"
Mbale,10,Valid,L5/6,150000,Fell,01/01/1992 12:00:00 AM,1.066670,34.166670,"(1.066670, 34.166670)"
Peekskill,11,Valid,H6,12400,Fell,01/01/1992 12:00:00 AM,41.283330,-73.916670,"(41.283330, -73.916670)"
MissingCoords,12,Valid,Iron,500000,Found,01/01/1995 12:00:00 AM,,,
EOF
chown ga:ga /home/ga/Documents/meteorite_landings.csv

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Sugar Terminal activity for the agent
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 5

# Verify Terminal is running
if pgrep -f "Terminal" > /dev/null 2>&1; then
    echo "Terminal activity is running"
else
    echo "WARNING: Terminal activity may not have started"
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/meteorite_task_start.png" 2>/dev/null || true

echo "=== meteorite_kml_generator task setup complete ==="