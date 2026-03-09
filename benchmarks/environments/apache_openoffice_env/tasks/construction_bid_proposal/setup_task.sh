#!/bin/bash
set -e
echo "=== Setting up Construction Bid Proposal Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Documents directory and clean up
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/Ironclad_Bid_Proposal_LSCU.odt 2>/dev/null || true
rm -f /home/ga/Documents/project_data.json 2>/dev/null || true

# 2. Create the project data JSON file
cat > /home/ga/Documents/project_data.json << 'JSONEOF'
{
  "document_info": {
    "proposal_number": "IBL-2025-P-0042",
    "proposal_date": "February 10, 2025",
    "submission_deadline": "February 21, 2025, 4:00 PM CST",
    "output_filename": "Ironclad_Bid_Proposal_LSCU.odt"
  },
  "contractor": {
    "company_name": "Ironclad Builders, LLC",
    "address": "1805 East 6th Street, Suite 110, Austin, TX 78702",
    "phone": "(512) 555-0193",
    "email": "proposals@ironcladbuilders.com",
    "website": "www.ironcladbuilders.com",
    "license_number": "TBPE-GC-048712"
  },
  "client": {
    "name": "Lone Star Credit Union",
    "contact_person": "Rebecca Torres, VP of Facilities",
    "address": "2400 South Lamar Boulevard, Austin, TX 78704",
    "rfp_number": "LSCU-RFP-2025-003"
  },
  "project": {
    "name": "Lone Star Credit Union — South Lamar Branch Office Renovation",
    "location": "2400 South Lamar Boulevard, Austin, TX 78704",
    "description": "Complete interior renovation of existing 12,000 SF single-story commercial building. Work includes selective demolition, structural modifications for vault, HVAC replacement, electrical rewiring, and high-end finishes.",
    "key_features": [
      "New reinforced vault room (800 SF)",
      "Drive-through teller canopy",
      "Open-plan member services area",
      "4 private office suites"
    ]
  },
  "cost_estimate": {
    "line_items": [
      {"division": "02", "description": "Demolition", "amount": 42800},
      {"division": "03", "description": "Concrete", "amount": 18500},
      {"division": "05", "description": "Metals", "amount": 67200},
      {"division": "07", "description": "Thermal & Moisture", "amount": 31400},
      {"division": "08", "description": "Openings", "amount": 48600},
      {"division": "09", "description": "Finishes", "amount": 156300},
      {"division": "10", "description": "Specialties", "amount": 12800},
      {"division": "21", "description": "Fire Suppression", "amount": 28900},
      {"division": "22", "description": "Plumbing", "amount": 52400},
      {"division": "23", "description": "HVAC", "amount": 187500},
      {"division": "26", "description": "Electrical", "amount": 118700},
      {"division": "27", "description": "Communications", "amount": 34200},
      {"division": "28", "description": "Safety & Security", "amount": 22500}
    ],
    "general_conditions": 68000,
    "contractor_fee": 71200,
    "contingency": 48000,
    "total_bid_price": 1009000,
    "total_bid_price_formatted": "$1,009,000"
  },
  "schedule": {
    "duration_weeks": 22,
    "milestones": [
      {"milestone": "Notice to Proceed", "date": "March 15, 2025"},
      {"milestone": "Demolition Complete", "date": "April 11, 2025"},
      {"milestone": "Rough-In Complete", "date": "June 6, 2025"},
      {"milestone": "Finishes Complete", "date": "July 25, 2025"},
      {"milestone": "Substantial Completion", "date": "August 15, 2025"}
    ]
  },
  "team": [
    {"name": "Carlos Mendoza, PMP", "role": "Project Manager"},
    {"name": "Sarah Chen, PE", "role": "Structural Engineer"},
    {"name": "Mike Driscoll", "role": "Superintendent"}
  ],
  "required_sections": [
    "Cover Page", "Executive Summary", "Scope of Work", "Cost Summary",
    "Project Schedule", "Qualifications", "Terms and Conditions"
  ]
}
JSONEOF
chown ga:ga /home/ga/Documents/project_data.json
chmod 644 /home/ga/Documents/project_data.json

# 3. Create desktop shortcut for Writer if missing
if [ ! -f "/home/ga/Desktop/openoffice-writer.desktop" ]; then
    mkdir -p /home/ga/Desktop
    cat > /home/ga/Desktop/openoffice-writer.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenOffice Writer
Comment=Create and edit text documents
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=openoffice4-writer
Terminal=false
Categories=Office;WordProcessor;
DESKTOP
    chown -R ga:ga /home/ga/Desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
fi

# 4. Record task start time and initial state
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_size.txt

# 5. Launch OpenOffice Writer to save agent time
# (Task focus is on document creation, not app launching)
if ! pgrep -f "soffice" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "OpenOffice Writer"; then
            break
        fi
        sleep 1
    done
    
    # Maximize
    DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Data file: /home/ga/Documents/project_data.json"
echo "Target: /home/ga/Documents/Ironclad_Bid_Proposal_LSCU.odt"