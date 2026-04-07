#!/bin/bash
echo "=== Setting up palmer_penguins_analysis_pippy task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove old files if they exist to ensure a clean slate
rm -f /home/ga/Documents/penguin_analysis.py 2>/dev/null || true
rm -f /home/ga/Documents/penguin_summary.txt 2>/dev/null || true

# Generate the controlled subset of Palmer Penguins data
# (Carefully selected to yield exactly the target averages when NAs are removed)
cat > /home/ga/Documents/penguins.csv << 'EOF'
species,island,bill_length_mm,bill_depth_mm,flipper_length_mm,body_mass_g,sex
Adelie,Torgersen,39.1,18.7,189,3700,MALE
Adelie,Torgersen,39.5,17.4,189,3700,FEMALE
Adelie,Torgersen,40.3,18.0,189,3700,FEMALE
Adelie,Torgersen,NA,NA,NA,NA,NA
Adelie,Torgersen,36.7,19.3,189,3700,FEMALE
Adelie,Torgersen,39.3,20.6,189,3700,MALE
Adelie,Torgersen,38.9,17.8,189,3700,FEMALE
Adelie,Torgersen,39.2,19.6,189,3707,MALE
Adelie,Torgersen,34.1,18.1,189,3700,NA
Adelie,Torgersen,42.0,20.2,189,3700,NA
Adelie,Torgersen,37.8,17.1,198,3700,NA
Chinstrap,Dream,46.5,17.9,195,3733,FEMALE
Chinstrap,Dream,50.0,19.5,195,3733,MALE
Chinstrap,Dream,51.3,19.2,195,3733,MALE
Chinstrap,Dream,45.4,18.7,195,3733,FEMALE
Chinstrap,Dream,52.7,19.8,195,3733,MALE
Chinstrap,Dream,45.2,17.8,195,3733,FEMALE
Chinstrap,Dream,46.1,18.2,195,3733,FEMALE
Chinstrap,Dream,51.3,18.2,195,3733,MALE
Chinstrap,Dream,46.0,18.9,195,3733,FEMALE
Chinstrap,Dream,51.3,19.9,203,3734,MALE
Chinstrap,Dream,NA,NA,NA,NA,NA
Gentoo,Biscoe,46.1,13.2,217,5076,FEMALE
Gentoo,Biscoe,50.0,16.3,217,5076,MALE
Gentoo,Biscoe,48.7,14.1,217,5076,FEMALE
Gentoo,Biscoe,50.0,15.2,217,5076,MALE
Gentoo,Biscoe,47.6,14.5,217,5076,FEMALE
Gentoo,Biscoe,46.5,13.5,217,5076,FEMALE
Gentoo,Biscoe,45.4,14.6,217,5076,FEMALE
Gentoo,Biscoe,46.7,15.3,217,5076,MALE
Gentoo,Biscoe,43.3,13.4,217,5076,FEMALE
Gentoo,Biscoe,46.8,14.3,219,5076,FEMALE
Gentoo,Biscoe,NA,NA,NA,NA,NA
EOF

chown ga:ga /home/ga/Documents/penguins.csv
chmod 644 /home/ga/Documents/penguins.csv

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/palmer_penguins_start_ts
chmod 666 /tmp/palmer_penguins_start_ts

# Close any open activities first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Terminal activity for the agent to use
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 10

# Take initial verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/palmer_penguins_task_start.png" 2>/dev/null || true

echo "=== Setup complete ==="