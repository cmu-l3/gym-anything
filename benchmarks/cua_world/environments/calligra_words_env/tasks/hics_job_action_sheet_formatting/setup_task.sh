#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up HICS JAS Formatting Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/hics_jas_raw.odt
rm -f /home/ga/Documents/hics_jas_formatted.odt
rm -f /home/ga/Desktop/jas_formatting_requirements.txt

# Create the requirements file
cat > /home/ga/Desktop/jas_formatting_requirements.txt << 'EOF'
HICS JOB ACTION SHEET FORMATTING REQUIREMENTS

You must format the raw HICS Job Action Sheet document into a binder-ready set of job aids. Please follow these strict guidelines:

1. PAGINATION: Every role must start on a new page. Insert a Page Break immediately before each "JOB ACTION SHEET:" title. (There are 4 roles in total).

2. MAIN TITLES: 
   - Format each "JOB ACTION SHEET: [Role]" line as Heading 1.
   - Center align these titles.

3. POSITION DETAILS TABLE:
   - For each role, there are three lines of metadata: "Reports To:", "Command Center Location:", and "Radio Title:".
   - Convert these three lines into a 2-column table for readability. (Put the label in column 1 and the value in column 2).

4. TIME-PHASE SUBHEADINGS:
   - Format the time phases (e.g., "Immediate Actions (0-2 Hours)", "Intermediate Actions (2-12 Hours)", "Extended Actions (12+ Hours)") as Heading 2.

5. ACTION LISTS:
   - The action items under each phase are currently just plain text with numbers. Convert them into proper Numbered Lists using the word processor's list tool.

6. SAFETY NOTES:
   - Any paragraph that begins with the exact phrase "SAFETY NOTE:" must be formatted as Bold text to ensure high visibility.

SAVE:
Save the completed file as 'hics_jas_formatted.odt' in your Documents folder.
EOF

chown ga:ga /home/ga/Desktop/jas_formatting_requirements.txt

# Create the unformatted ODT
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_p(text):
    doc.text.addElement(P(text=text))

add_p("JOB ACTION SHEET: Incident Commander")
add_p("Reports To: Hospital Administrator")
add_p("Command Center Location: Main Conference Room A")
add_p("Radio Title: Incident Command")
add_p("Immediate Actions (0-2 Hours)")
add_p("1. Read this entire Job Action Sheet and review the organizational chart.")
add_p("2. Establish the Hospital Command Center (HCC).")
add_p("3. Appoint Section Chiefs (Operations, Planning, Logistics, Finance).")
add_p("SAFETY NOTE: Ensure personal protective equipment (PPE) requirements are communicated immediately if a hazmat or biological threat is suspected.")
add_p("Intermediate Actions (2-12 Hours)")
add_p("1. Conduct regular briefings with the Command Staff.")
add_p("2. Authorize resources as requested by the Logistics Section Chief.")
add_p("3. Communicate status to local EMS and emergency management agencies.")
add_p("Extended Actions (12+ Hours)")
add_p("1. Develop a demobilization plan.")
add_p("2. Ensure staff rehabilitation and shift rotations are established.")

add_p("JOB ACTION SHEET: Medical Care Branch Director")
add_p("Reports To: Operations Section Chief")
add_p("Command Center Location: ED Control Desk")
add_p("Radio Title: Medical Branch")
add_p("Immediate Actions (0-2 Hours)")
add_p("1. Read this entire Job Action Sheet.")
add_p("2. Ensure triage protocols are activated at all patient points of entry.")
add_p("3. Assess current bed availability and rapid discharge potential.")
add_p("SAFETY NOTE: Monitor staff for heat stress and fatigue if Level C or higher PPE is deployed.")
add_p("Intermediate Actions (2-12 Hours)")
add_p("1. Coordinate with Logistics for emergency medical supplies.")
add_p("2. Establish alternate care sites if emergency department capacity is exceeded.")
add_p("Extended Actions (12+ Hours)")
add_p("1. Oversee the transition of care to routine operational protocols.")
add_p("2. Ensure complete documentation of all clinical interventions.")

add_p("JOB ACTION SHEET: Security Branch Director")
add_p("Reports To: Operations Section Chief")
add_p("Command Center Location: Security Operations Center")
add_p("Radio Title: Security Branch")
add_p("Immediate Actions (0-2 Hours)")
add_p("1. Read this entire Job Action Sheet.")
add_p("2. Initiate facility lockdown procedures if the threat is external.")
add_p("3. Secure the Emergency Department perimeter and triage areas.")
add_p("SAFETY NOTE: Verify all facility access points are controlled before assigning staff to exterior posts.")
add_p("Intermediate Actions (2-12 Hours)")
add_p("1. Coordinate with local law enforcement for traffic control.")
add_p("2. Provide crowd control for the family reunification area.")
add_p("Extended Actions (12+ Hours)")
add_p("1. Establish a long-term credentialing protocol for supplemental staff.")
add_p("2. Conduct post-incident debriefings with the security team.")

add_p("JOB ACTION SHEET: Public Information Officer")
add_p("Reports To: Incident Commander")
add_p("Command Center Location: First Floor Briefing Room")
add_p("Radio Title: PIO")
add_p("Immediate Actions (0-2 Hours)")
add_p("1. Read this entire Job Action Sheet.")
add_p("2. Establish a media staging area away from patient care zones.")
add_p("3. Draft an initial press statement and obtain Incident Commander approval.")
add_p("SAFETY NOTE: Do not release patient names or identifiable data under any circumstances without direct HIPAA clearance.")
add_p("Intermediate Actions (2-12 Hours)")
add_p("1. Schedule regular press briefings.")
add_p("2. Monitor social media and correct any misinformation regarding the hospital's status.")
add_p("Extended Actions (12+ Hours)")
add_p("1. Coordinate with the Joint Information Center (JIC) if activated by the city/county.")
add_p("2. Provide final summary reports to the media.")

doc.save("/home/ga/Documents/hics_jas_raw.odt")
PYEOF

chown ga:ga /home/ga/Documents/hics_jas_raw.odt

# Record task start time (for anti-gaming timestamps)
date +%s > /tmp/task_start_time.txt

# Launch Calligra Words and wait
launch_calligra_document "/home/ga/Documents/hics_jas_raw.odt"
wait_for_window "Calligra Words\|calligrawords" 30

# Maximize window
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="