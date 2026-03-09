#!/bin/bash
set -e
echo "=== Setting up Clinical Site Visit Report Task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare directories and clean state
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/IMV_Report_Site_142.odt 2>/dev/null || true
rm -f /home/ga/Documents/visit_notes.json 2>/dev/null || true

# 2. Create the Input Data JSON
cat > /home/ga/Documents/visit_notes.json << 'EOF'
{
  "protocol": {
    "number": "ZN-994",
    "title": "A Phase III, Randomized, Double-Blind Study of Zenicor in Patients with Resistant Hypertension",
    "sponsor": "Zenith Pharmaceuticals"
  },
  "visit": {
    "site_number": "142",
    "site_name": "Memorial Hospital",
    "location": "Seattle, WA",
    "date": "2024-03-15",
    "type": "Interim Monitoring Visit (IMV)",
    "monitor": "Alex Rivera",
    "personnel_met": [
      "Dr. Elena Rostova (Principal Investigator)",
      "Sarah Chen (Study Coordinator)",
      "Marcus Thorne (Pharmacist)"
    ]
  },
  "enrollment": {
    "screened": 18,
    "randomized": 14,
    "completed": 3,
    "discontinued": 2,
    "note": "Please calculate Active subjects for the report table (Active = Randomized - Completed - Discontinued)"
  },
  "deviations": [
    {
      "id": "DEV-001",
      "date": "2024-02-10",
      "description": "Subject 142-004 missed Visit 4 window by 3 days due to patient vacation.",
      "irb_reported": true
    },
    {
      "id": "DEV-002",
      "date": "2024-02-28",
      "description": "Temperature excursion in drug storage refrigerator. Temp reached 9.1°C for 2 hours during power outage.",
      "irb_reported": true
    }
  ],
  "ip_accountability": {
    "status": "Acceptable",
    "comments": "Drug accountability logs reviewed. 98% compliance. Temperature excursion noted in deviations."
  },
  "action_items": [
    {
      "id": "AI-01",
      "description": "Obtain PI signature on lab reports for Subject 142-008",
      "owner": "Sarah Chen",
      "status": "Closed",
      "due_date": "2024-03-15"
    },
    {
      "id": "AI-02",
      "description": "Submit temperature excursion report to Sponsor Safety Team",
      "owner": "Alex Rivera",
      "status": "Open",
      "due_date": "2024-03-20"
    },
    {
      "id": "AI-03",
      "description": "Re-train study nurse on blood pressure measurement guidelines",
      "owner": "Dr. Rostova",
      "status": "Open",
      "due_date": "2024-03-30"
    }
  ]
}
EOF
chown ga:ga /home/ga/Documents/visit_notes.json

# 3. Launch OpenOffice Writer (Starting State Requirement)
echo "Launching OpenOffice Writer..."
if ! pgrep -f "soffice" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
            break
        fi
        sleep 1
    done
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# 4. Record anti-gaming timestamps
date +%s > /tmp/task_start_time.txt

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="