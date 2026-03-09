#!/bin/bash
# setup_task.sh for pm_schedule_create

set -e
echo "=== Setting up PM Schedule Document Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure target directory exists and has correct permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any existing output file (clean state)
rm -f /home/ga/Documents/CRWA_PM_Schedule_FY2025.odt

# Create the plant equipment JSON data file
cat > /home/ga/Documents/plant_equipment.json << 'JSONEOF'
{
  "document_info": {
    "document_number": "PM-CRWA-FY2025-001",
    "title": "Preventive Maintenance Schedule — Fiscal Year 2025",
    "effective_date": "2024-07-01",
    "revision": "1.0",
    "prepared_by": "Marcus Delgado, Lead Maintenance Technician",
    "approved_by": "Patricia Kowalski, Plant Superintendent"
  },
  "plant_info": {
    "utility_name": "Clearwater Regional Water Authority",
    "plant_name": "Long Creek Water Treatment Plant",
    "address": "2200 Reservoir Drive, Gastonia, NC 28054",
    "capacity_mgd": 12
  },
  "equipment": [
    {"asset_tag": "RWP-001", "description": "Raw Water Intake Pump #1", "manufacturer": "Xylem Flygt", "location": "Raw Water Intake"},
    {"asset_tag": "RWP-002", "description": "Raw Water Intake Pump #2", "manufacturer": "Xylem Flygt", "location": "Raw Water Intake"},
    {"asset_tag": "RMX-001", "description": "Rapid Mix Chemical Feeder", "manufacturer": "LMI Milton Roy", "location": "Chemical Feed Room"},
    {"asset_tag": "FBD-001", "description": "Flocculation Basin Drive Unit", "manufacturer": "Philadelphia Mixers", "location": "Flocculation Basin"},
    {"asset_tag": "SSC-001", "description": "Sedimentation Sludge Collector", "manufacturer": "Evoqua", "location": "Sedimentation Basin"},
    {"asset_tag": "DMF-001", "description": "Dual Media Gravity Filter Bank", "manufacturer": "Leopold/Xylem", "location": "Filter Gallery"},
    {"asset_tag": "BWP-001", "description": "Filter Backwash Pump", "manufacturer": "Goulds", "location": "Pump Room 201"},
    {"asset_tag": "CDG-001", "description": "Chlorine Dioxide Generator", "manufacturer": "ProMinent", "location": "Chemical Feed Room 104"},
    {"asset_tag": "UVD-001", "description": "UV Disinfection System", "manufacturer": "Trojan Technologies", "location": "UV Chamber"},
    {"asset_tag": "CTP-001", "description": "Clearwell Transfer Pump", "manufacturer": "Grundfos", "location": "Pump Room 202"},
    {"asset_tag": "HSD-001", "description": "High Service Distribution Pump", "manufacturer": "Peerless Pump", "location": "HS Pump Station"},
    {"asset_tag": "GEN-001", "description": "Emergency Standby Generator", "manufacturer": "Caterpillar", "location": "Generator Building"}
  ],
  "pm_tasks": {
    "daily": [
      {"id": "D-001", "desc": "Visual inspection of all operating pumps for leaks/noise", "resp": "Operator"},
      {"id": "D-002", "desc": "Record chemical feed pump stroke rate", "resp": "Operator"},
      {"id": "D-003", "desc": "Check ClO2 generator residual output", "resp": "Operator"}
    ],
    "weekly": [
      {"id": "W-001", "desc": "Grease flocculation basin drive bearings", "resp": "Maintenance Tech"},
      {"id": "W-002", "desc": "Inspect sludge collector chain tension", "resp": "Maintenance Tech"},
      {"id": "W-003", "desc": "Exercise emergency generator under load (30 mins)", "resp": "Maintenance Tech"}
    ],
    "monthly": [
      {"id": "M-001", "desc": "Vibration readings on all pump motors", "resp": "Lead Tech"},
      {"id": "M-002", "desc": "Oil analysis for high service pumps", "resp": "Lead Tech"},
      {"id": "M-003", "desc": "Calibrate chlorine dioxide analyzer", "resp": "I&C Specialist"}
    ],
    "quarterly": [
      {"id": "Q-001", "desc": "Full vibration spectrum analysis", "resp": "Contractor"},
      {"id": "Q-002", "desc": "Laser shaft alignment check", "resp": "Lead Tech"}
    ],
    "annual": [
      {"id": "A-001", "desc": "Full pump teardown and rebuild (2 pumps/year)", "resp": "Contractor"},
      {"id": "A-002", "desc": "Generator 250-hour major service", "resp": "Caterpillar Dealer"}
    ]
  }
}
JSONEOF

chown ga:ga /home/ga/Documents/plant_equipment.json
chmod 644 /home/ga/Documents/plant_equipment.json

# Launch Apache OpenOffice Writer so it's ready for the agent
if ! pgrep -f "soffice" > /dev/null; then
    echo "Starting OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "OpenOffice"; then
            echo "Writer window found"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "OpenOffice" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice" 2>/dev/null || true

# Dismiss "Welcome" or "Recovery" dialogs if they appear
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="