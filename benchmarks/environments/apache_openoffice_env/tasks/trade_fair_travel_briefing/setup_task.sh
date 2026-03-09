#!/bin/bash
set -e
echo "=== Setting up Trade Fair Travel Briefing Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous output file to ensure clean state
rm -f /home/ga/Documents/Sterling_Hannover_Messe_Briefing_2025.odt

# Create the delegation data JSON file
cat > /home/ga/Documents/delegation_data.json << 'JSONEOF'
{
  "document_info": {
    "title": "Hannover Messe 2025 — Executive Delegation Travel Briefing",
    "document_number": "SDG-TRAVEL-2025-017",
    "prepared_by": "Lorena Marchetti, Executive Assistant to CEO",
    "company": "Sterling Dynamics Group, LLC",
    "company_address": "5000 W. Florist Avenue, Milwaukee, WI 53218"
  },
  "event": {
    "name": "Hannover Messe 2025",
    "dates": "April 28 – May 2, 2025",
    "venue": "Deutsche Messe AG, Messegelände, 30521 Hannover, Germany"
  },
  "delegation": [
    {
      "name": "Catherine Albrecht",
      "title": "Chief Executive Officer",
      "mobile": "+1 (414) 555-0201",
      "passport_number": "562847391"
    },
    {
      "name": "Marcus Oduya",
      "title": "Vice President, International Sales",
      "mobile": "+1 (414) 555-0218",
      "passport_number": "483920156"
    },
    {
      "name": "Dr. Ingrid Svensson",
      "title": "Chief Technology Officer",
      "mobile": "+1 (414) 555-0234",
      "passport_number": "671035824"
    },
    {
      "name": "Raymond Delacroix",
      "title": "Director of Business Development",
      "mobile": "+1 (414) 555-0247",
      "passport_number": "529461078"
    }
  ],
  "travel_itinerary": {
    "outbound": [
      {
        "date": "2025-04-27",
        "segment": "Flight",
        "details": "Chicago ORD to Frankfurt FRA",
        "flight_number": "LH 431",
        "departure": "18:10",
        "arrival": "08:25+1"
      },
      {
        "date": "2025-04-28",
        "segment": "Train",
        "details": "Frankfurt Hbf to Hannover Hbf",
        "train_number": "ICE 577",
        "departure": "10:17",
        "arrival": "12:40"
      }
    ],
    "return": [
      {
        "date": "2025-05-02",
        "segment": "Train",
        "details": "Hannover Hbf to Frankfurt Flughafen",
        "train_number": "ICE 874",
        "departure": "15:27",
        "arrival": "18:03"
      },
      {
        "date": "2025-05-02",
        "segment": "Flight",
        "details": "Frankfurt FRA to Chicago ORD",
        "flight_number": "LH 430",
        "departure": "20:15",
        "arrival": "22:40"
      }
    ]
  },
  "hotel": {
    "name": "Courtyard by Marriott Hannover Maschsee",
    "address": "Arthur-Menge-Ufer 3, 30169 Hannover, Germany",
    "phone": "+49 511 940-880",
    "confirmation": "MRHT-84629317"
  },
  "meeting_schedule": [
    {
      "date": "2025-04-28",
      "meetings": [
        {"time": "14:30", "partner": "Siemens Digital Industries", "location": "Hall 9, Booth A42"},
        {"time": "16:00", "partner": "Renishaw GmbH", "location": "Hall 6, Booth F38"}
      ]
    },
    {
      "date": "2025-04-29",
      "meetings": [
        {"time": "09:30", "partner": "Trumpf Werkzeugmaschinen", "location": "Hall 4, Booth D22"},
        {"time": "11:00", "partner": "Hexagon Manufacturing Intelligence", "location": "Hall 6, Booth C14"},
        {"time": "14:00", "partner": "Balluff GmbH", "location": "Hall 9, Booth E27"},
        {"time": "16:30", "partner": "Schaeffler Group", "location": "Hall 22, Booth A18"}
      ]
    },
    {
      "date": "2025-04-30",
      "meetings": [
        {"time": "09:00", "partner": "Mitsubishi Electric Europe", "location": "Hall 11, Booth B50"},
        {"time": "11:30", "partner": "Fraunhofer Institute (IPT)", "location": "Hall 17, Booth K09"}
      ]
    }
  ],
  "emergency_contacts": [
    {"name": "European Emergency", "phone": "112"},
    {"name": "U.S. Embassy Berlin", "phone": "+49 30 8305-0"},
    {"name": "Medizinische Hochschule Hannover", "phone": "+49 511 532-0"},
    {"name": "Lorena Marchetti (Assistant)", "phone": "+1 (414) 555-0192"}
  ]
}
JSONEOF

chown ga:ga /home/ga/Documents/delegation_data.json

# Kill any existing OpenOffice instances
pkill -f soffice 2>/dev/null || true
sleep 1

# Launch Apache OpenOffice Writer
echo "Launching OpenOffice Writer..."
su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice"; then
        echo "OpenOffice Writer window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "OpenOffice" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss any startup dialogs (Welcome Wizard)
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="