#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Emergency Action Plan Format Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/emergency_action_plan_start_ts

# Create necessary directories
sudo -u ga mkdir -p /home/ga/Documents

# Generate the unformatted DOCX file
python3 << 'PYEOF'
from docx import Document

doc = Document()

# Create completely unformatted text to force the agent to format it
doc.add_paragraph("Emergency Action Plan — Meridian Business Center")
doc.add_paragraph("")

doc.add_paragraph("Purpose and Scope")
doc.add_paragraph("The purpose of this Emergency Action Plan (EAP) is to establish procedures for the safe and orderly evacuation or sheltering of employees and visitors at the Meridian Business Center during emergency situations. This plan complies with OSHA Standard 29 CFR 1910.38.")
doc.add_paragraph("")

doc.add_paragraph("Building Information")
doc.add_paragraph("The Meridian Business Center is located at 450 Commerce Drive, Springfield, IL 62701. The building consists of 4 floors above ground, with approximately 280 regular occupants. Normal operating hours are 7:00 AM to 6:00 PM, Monday through Friday.")
doc.add_paragraph("")

doc.add_paragraph("Emergency Contact Directory")
doc.add_paragraph("The following individuals are the primary emergency contacts. John Smith is the Building Manager (Office Phone: 555-0101, Cell Phone: 555-0201). Jane Doe is the Security Director (Office Phone: 555-0102, Cell Phone: 555-0202). Robert Jones is the Facilities Supervisor (Office Phone: 555-0103, Cell Phone: 555-0203). Sarah Lee is the Property Manager (Office Phone: 555-0104, Cell Phone: 555-0204). Michael Chen is the Lead Engineer (Office Phone: 555-0105, Cell Phone: 555-0205). Emily White is the Health and Safety Coordinator (Office Phone: 555-0106, Cell Phone: 555-0206).")
doc.add_paragraph("")

doc.add_paragraph("Evacuation Procedures")
doc.add_paragraph("Evacuation may be required in the event of fire, chemical spill, or structural damage.")
doc.add_paragraph("Fire Evacuation")
doc.add_paragraph("In the event of a fire, DO NOT use elevators. You must EVACUATE immediately using the nearest stairwell and proceed to the designated assembly point.")
doc.add_paragraph("Floor Warden Assignments")
doc.add_paragraph("Floor 1: Primary Warden is Alice Brown, Alternate Warden is Bob White. Floor 2: Primary Warden is Charlie Green, Alternate Warden is Diana Black. Floor 3: Primary Warden is Edward Stone, Alternate Warden is Fiona Grey. Floor 4: Primary Warden is George Taylor, Alternate Warden is Helen Clark.")
doc.add_paragraph("Assembly Point Locations")
doc.add_paragraph("When evacuating, use the designated routes and proceed to the assembly points. For the North Exit, the route description is via the Main Lobby, and the Assembly Point is North Parking Lot A. For the South Exit, the route description is via the Cafeteria, and the Assembly Point is the South Lawn. For the East Exit, the route description is via the Service Corridor, and the Assembly Point is the East Annex Courtyard. For the West Exit, the route description is via the Loading Dock, and the Assembly Point is West Street Sidewalk.")
doc.add_paragraph("")

doc.add_paragraph("Shelter-in-Place Procedures")
doc.add_paragraph("Severe Weather")
doc.add_paragraph("For a tornado warning or severe weather event, SHELTER IN PLACE in the interior core of the building, away from windows and exterior doors.")
doc.add_paragraph("Earthquake")
doc.add_paragraph("Drop, cover, and hold on during the shaking. Once the shaking stops, wait for instructions from floor wardens.")
doc.add_paragraph("")

doc.add_paragraph("Active Threat Response")
doc.add_paragraph("In the event of an active shooter or hostile intruder, if you cannot safely escape the building, initiate LOCKDOWN procedures in your current room. Barricade the door, turn off lights, and remain silent. Always CALL 911 for emergencies when it is safe to do so.")
doc.add_paragraph("")

doc.add_paragraph("Emergency Equipment and Resources")
doc.add_paragraph("The following emergency equipment is available throughout the facility. Fire Extinguishers are located in All Hallways with a quantity of 12. AEDs are located at the Reception and Security Desk with a quantity of 2. First Aid Kits are located in the Break Rooms with a quantity of 4. Evacuation Chairs are located in the Stairwells with a quantity of 4.")
doc.add_paragraph("")

doc.add_paragraph("Training and Drills")
doc.add_paragraph("All employees must receive EAP training upon initial assignment. Fire drills are conducted semi-annually, and severe weather drills are conducted annually prior to the spring storm season.")

# Ensure everything is "Normal" style to require agent to format
for para in doc.paragraphs:
    para.style = doc.styles['Normal']

doc.save('/home/ga/Documents/emergency_action_plan_raw.docx')
PYEOF

sudo chown ga:ga /home/ga/Documents/emergency_action_plan_raw.docx
sudo chmod 644 /home/ga/Documents/emergency_action_plan_raw.docx

# Launch WPS Writer with the document
echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 wps /home/ga/Documents/emergency_action_plan_raw.docx > /dev/null 2>&1 &"
sleep 5

# Dismiss any potential first-run dialogs
dismiss_wps_dialogs 2>/dev/null || true

# Maximize and focus WPS Writer
WID=$(get_wps_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Ensure it's focused again
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/emergency_action_plan_initial.png

echo "=== Task Setup Complete ==="