#!/bin/bash
# Setup script for Security Post Orders task
# Creates the JSON data file and ensures OpenOffice is ready

echo "=== Setting up Security Post Orders Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Clean up any previous run artifacts
rm -f /home/ga/Documents/SPO-HBC-2024-003.odt 2>/dev/null || true
rm -f /home/ga/Documents/site_security_data.json 2>/dev/null || true

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Create the detailed JSON data file
cat > /home/ga/Documents/site_security_data.json << 'EOF'
{
  "company": {
    "name": "Sentinel Shield Security Services, LLC",
    "address": "2750 Monroe Boulevard, Suite 110, Audubon, PA 19403",
    "phone": "610-555-0199",
    "license": "PA-MP-10442"
  },
  "client": {
    "name": "Helios BioSciences, Inc.",
    "site_name": "Helios Research Campus",
    "address": "1400 Pharmaceutical Drive, Collegeville, PA 19426",
    "description": "3-building campus, 18.5 acres, BSL-2 laboratories, pilot manufacturing.",
    "employees": 420,
    "hours": "24/7/365"
  },
  "document": {
    "title": "Security Post Orders",
    "document_number": "SPO-HBC-2024-003",
    "classification": "CONFIDENTIAL",
    "effective_date": "March 15, 2024",
    "prepared_by": "Sarah Jenkins, CPP - Account Manager",
    "approved_by": "David Chen - Director of Global Security"
  },
  "posts": [
    {
      "id": "POST-01",
      "name": "Security Command Center (SCC)",
      "location": "Building A, Lobby",
      "hours": "24/7",
      "staffing": "1 Supervisor, 1 Console Operator",
      "duties": ["Monitor CCTV and access control alarms", "Dispatch roving patrols", "Manage badge creation", "Emergency communications"]
    },
    {
      "id": "POST-02",
      "name": "Main Gate / Reception",
      "location": "Building A, Main Entrance",
      "hours": "07:00 - 19:00, Mon-Fri",
      "staffing": "1 Security Officer",
      "duties": ["Visitor processing and badging", "Vehicle inspections", "Mail/package screening", "Lobby reception"]
    },
    {
      "id": "POST-03",
      "name": "Loading Dock",
      "location": "Building B, Rear",
      "hours": "06:00 - 18:00, Mon-Fri",
      "staffing": "1 Security Officer",
      "duties": ["Verify delivery manifests", "Inspect incoming shipments", "Control vendor access", "Monitor waste removal"]
    },
    {
      "id": "POST-04",
      "name": "Roving Patrol",
      "location": "Campus-wide",
      "hours": "24/7",
      "staffing": "1 Security Officer",
      "duties": ["Interior and exterior patrols", "Door checks", "Parking enforcement", "Escort duties"]
    }
  ],
  "patrol_checkpoints": [
    {"id": "CP-01", "location": "Bldg A Server Room", "check": "Temp/Humidity, Door Locked"},
    {"id": "CP-02", "location": "Bldg A Mechanical Room", "check": "No leaks, Panel secure"},
    {"id": "CP-03", "location": "Bldg B Chemical Storage", "check": "Ventilation running, No spills"},
    {"id": "CP-04", "location": "Bldg B Loading Dock", "check": "Roll-up doors closed"},
    {"id": "CP-05", "location": "Bldg C Pilot Plant", "check": "Badge reader functional"},
    {"id": "CP-06", "location": "Perimeter Fence North", "check": "Fence integrity"},
    {"id": "CP-07", "location": "Main Generator", "check": "Fuel level, Panel normal"},
    {"id": "CP-08", "location": "Parking Lot D", "check": "Lighting functional"}
  ],
  "access_levels": [
    {"level": "1", "color": "Green", "areas": "Lobby, Cafeteria, General Office", "personnel": "All Employees, Contractors"},
    {"level": "2", "color": "Blue", "areas": "Labs, Server Rooms", "personnel": "Lab Staff, IT"},
    {"level": "3", "color": "Red", "areas": "Pilot Plant, Chem Storage", "personnel": "Manufacturing, EHS"},
    {"level": "4", "color": "Yellow", "areas": "Security CC, IDF/MDF", "personnel": "Security, IT Admin"},
    {"level": "5", "color": "Black", "areas": "All Areas", "personnel": "Executive Team, Emergency Responders"}
  ],
  "emergency_procedures": {
    "fire": ["Activate nearest pull station", "Call 911 and SCC", "Evacuate to Assembly Point A", "Account for personnel", "Do not use elevators", "Assist mobility-impaired", "Await Fire Department instruction"],
    "medical": ["Call SCC immediately", "Dispatch patrol with AED", "Call 911 if life-threatening", "Clear path for EMS", "Provide First Aid/CPR if trained", "Protect patient privacy"],
    "intrusion_unauthorized_access": ["Observe and report description", "Do not confront if hostile", "Lockdown affected area via CCURE", "Dispatch patrol to investigate", "Notify police if weapon seen", "Preserve crime scene"],
    "hazmat_chemical_spill": ["Evacuate immediate area", "Isolate the zone", "Identify chemical if safe", "Notify EHS and SCC", "Consult SDS", "Do not attempt cleanup unless trained"]
  },
  "contacts": [
    {"role": "Security Command Center", "name": "Dispatch", "phone": "x4400 / 610-555-0100"},
    {"role": "Client Contact (Primary)", "name": "David Chen", "phone": "610-555-0105"},
    {"role": "Client Contact (Secondary)", "name": "Maria Rodriguez (Facilities)", "phone": "610-555-0108"},
    {"role": "Sentinel Account Manager", "name": "Sarah Jenkins", "phone": "215-555-0992"},
    {"role": "Collegeville Police", "name": "Emergency / Non-Emergency", "phone": "911 / 610-489-9332"},
    {"role": "Collegeville Fire", "name": "Dispatch", "phone": "911 / 610-489-0600"},
    {"role": "Facilities Helpdesk", "name": "24/7 Line", "phone": "xHELP (4357)"},
    {"role": "IT Security SOC", "name": "24/7 Line", "phone": "xCYBER (2923)"},
    {"role": "EHS Officer", "name": "Dr. Alan Grant", "phone": "xSAFE (7233)"},
    {"role": "Building Landlord", "name": "PharmaProps Mgmt", "phone": "610-555-8800"}
  ],
  "shift_schedule": [
    {"shift": "Alpha (1st)", "hours": "07:00 - 15:00", "staffing": "1 Sup, 3 Officers", "supervisor": "Lt. Morrow"},
    {"shift": "Bravo (2nd)", "hours": "15:00 - 23:00", "staffing": "1 Sup, 2 Officers", "supervisor": "Sgt. Barnes"},
    {"shift": "Charlie (3rd)", "hours": "23:00 - 07:00", "staffing": "1 Sup, 1 Officer", "supervisor": "Sgt. Wilson"}
  ]
}
EOF

# Set correct ownership
chown ga:ga /home/ga/Documents/site_security_data.json

# Ensure OpenOffice Writer is running (task starts with application open)
if ! pgrep -f "soffice" > /dev/null 2>&1; then
    echo "Starting OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Writer"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Data file created at /home/ga/Documents/site_security_data.json"