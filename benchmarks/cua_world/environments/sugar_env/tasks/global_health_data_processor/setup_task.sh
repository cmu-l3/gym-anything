#!/bin/bash
# Do NOT use set -e
echo "=== Setting up global_health_data_processor task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents

# Remove any pre-existing files
rm -f /home/ga/Documents/process_health_data.py 2>/dev/null || true
rm -f /home/ga/Documents/critical_stunting.csv 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/global_health_data_start_ts
chmod 666 /tmp/global_health_data_start_ts

# Generate the global_stunting_2022.csv dataset
cat << 'EOF' > /home/ga/Documents/global_stunting_2022.csv
Country,Region,Year,Indicator,Percentage
Burundi,Africa,2022,Stunting,50.9
Eritrea,Africa,2022,Stunting,49.6
Niger,Africa,2022,Stunting,46.5
Yemen,Middle East,2022,Stunting,46.4
Papua New Guinea,Oceania,2022,Stunting,43.1
Guatemala,Latin America,2022,Stunting,42.8
Mozambique,Africa,2022,Stunting,37.0
Afghanistan,Asia,2022,Stunting,35.0
Pakistan,Asia,2022,Stunting,34.6
Chad,Africa,2022,Stunting,34.0
DR Congo,Africa,2022,Stunting,33.4
Angola,Africa,2022,Stunting,33.2
Central African Republic,Africa,2022,Stunting,32.5
Zambia,Africa,2022,Stunting,32.3
Mauritania,Africa,2022,Stunting,32.0
India,Asia,2022,Stunting,31.7
Nigeria,Africa,2022,Stunting,31.5
Ethiopia,Africa,2022,Stunting,31.4
Lesotho,Africa,2022,Stunting,31.4
Sudan,Africa,2022,Stunting,31.1
Rwanda,Africa,2022,Stunting,30.8
Sierra Leone,Africa,2022,Stunting,30.6
Burkina Faso,Africa,2022,Stunting,30.4
Haiti,Latin America,2022,Stunting,30.3
Honduras,Latin America,2022,Stunting,30.2
Uganda,Africa,2022,Stunting,30.0
Indonesia,Asia,2022,Stunting,29.2
Philippines,Asia,2022,Stunting,28.8
Bangladesh,Asia,2022,Stunting,28.0
Mali,Africa,2022,Stunting,27.6
Kenya,Africa,2022,Stunting,26.2
South Africa,Africa,2022,Stunting,21.4
Vietnam,Asia,2022,Stunting,19.6
Egypt,Middle East,2022,Stunting,17.0
Morocco,Africa,2022,Stunting,14.9
Mexico,Latin America,2022,Stunting,12.6
Peru,Latin America,2022,Stunting,12.1
Colombia,Latin America,2022,Stunting,10.8
Thailand,Asia,2022,Stunting,10.5
Argentina,Latin America,2022,Stunting,8.2
Brazil,Latin America,2022,Stunting,6.9
Turkey,Middle East,2022,Stunting,5.5
China,Asia,2022,Stunting,4.8
Russia,Europe,2022,Stunting,4.3
USA,North America,2022,Stunting,3.2
Canada,North America,2022,Stunting,2.5
Australia,Oceania,2022,Stunting,2.0
France,Europe,2022,Stunting,1.8
UK,Europe,2022,Stunting,1.4
Germany,Europe,2022,Stunting,1.2
Japan,Asia,2022,Stunting,1.0
EOF

chown ga:ga /home/ga/Documents/global_stunting_2022.csv

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Verify Sugar is running
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/health_task_start.png" 2>/dev/null || true

echo "=== global_health_data_processor task setup complete ==="
echo "Data generated. Agent must create script to filter >= 30.0 and sort descending."