#!/bin/bash
# Setup script for Banquet Event Order task

echo "=== Setting up Banquet Event Order Task ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Documents directory and clean up
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/BEO_MillerTech_Retreat.odt 2>/dev/null || true
rm -f /home/ga/Documents/event_logistics.json 2>/dev/null || true

# 2. Create the input JSON data file
cat > /home/ga/Documents/event_logistics.json << 'JSONEOF'
{
  "event_info": {
    "client_name": "Miller-Tech Solutions",
    "event_name": "Quarterly Strategy Retreat",
    "beo_number": "BEO-24-992",
    "date": "October 12, 2025",
    "sales_manager": "Elena Rosales",
    "on_site_contact": "Sarah Jenkins (555-0199)",
    "guarantee_count": 45
  },
  "schedule": [
    {
      "time_start": "07:30",
      "time_end": "08:30",
      "function": "Continental Breakfast",
      "room": "Grand Ballroom Foyer",
      "setup": "Buffet flow, 4 high-top tables",
      "menu": [
        "Assorted Fresh Pastries",
        "Smoked Salmon Bagels with Capers",
        "Seasonal Sliced Fruit",
        "Vegan Chia Parfaits",
        "Coffee/Tea Station"
      ],
      "av_needs": "Background Music"
    },
    {
      "time_start": "08:30",
      "time_end": "12:00",
      "function": "General Session",
      "room": "Grand Ballroom B",
      "setup": "Crescent Rounds of 6",
      "menu": ["Water Service on Tables", "Mid-morning Coffee Refresh @ 10:00"],
      "av_needs": "Podium, Wireless Lav Mic, 4K Projector, Screen, slide advancer"
    },
    {
      "time_start": "12:00",
      "time_end": "13:00",
      "function": "Working Lunch",
      "room": "Grand Ballroom B",
      "setup": "Existing Set",
      "menu": ["Boxed Lunch: Turkey Club, Quinoa Salad (V), or Roast Beef", "Assorted Sodas"],
      "av_needs": "None"
    }
  ],
  "estimated_total": "$4,250.00",
  "notes": "Client requires gluten-free options labeled clearly."
}
JSONEOF
chown ga:ga /home/ga/Documents/event_logistics.json
chmod 644 /home/ga/Documents/event_logistics.json

# 3. Ensure OpenOffice Writer is available (create desktop shortcut if missing)
if [ ! -f "/home/ga/Desktop/openoffice-writer.desktop" ]; then
    mkdir -p /home/ga/Desktop
    cat > /home/ga/Desktop/openoffice-writer.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenOffice Writer
Comment=Create and edit text documents
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=/opt/openoffice4/program/soffice
Terminal=false
Categories=Office;WordProcessor;
DESKTOP
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
fi

# 4. Record baseline state
echo "0" > /tmp/initial_beo_exists
date +%s > /tmp/task_start_timestamp

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Input data: /home/ga/Documents/event_logistics.json"
echo "Target output: /home/ga/Documents/BEO_MillerTech_Retreat.odt"