#!/bin/bash
echo "=== Setting up chemical_exposure_symptom_diagnosis task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Desktop

# clean up previous run
rm -f /home/ga/Documents/exposure_diagnosis_report.txt

# Create the Incident Reports file on Desktop
cat > /home/ga/Desktop/incident_reports.txt << 'EOF'
INCIDENT INVESTIGATION LOG
Date: March 2, 2026
Facility: Chemical Storage Area 4

FACILITY INVENTORY (Suspect Chemicals):
1. Hydrogen Sulfide (CAS: 7783-06-4)
2. Hydrofluoric Acid (CAS: 7664-39-3)
3. Phenol (CAS: 108-95-2)
4. Nitrogen Dioxide (CAS: 10102-44-0)
5. Sulfuric Acid (CAS: 7664-93-9)

INCIDENT REPORTS:

Incident A
Time: 09:15
Description: Worker reported a strong rotten-egg odor initially, but after 5 minutes claimed the smell had disappeared and removed their respirator, believing the gas was gone. They were later found experiencing dizziness.

Incident B
Time: 11:30
Description: Worker splashed liquid on their forearm. They washed it off immediately and reported no pain or redness at the time. Six hours later, they are in excruciating deep-tissue pain, even though the skin surface still looks relatively normal with only mild erythema.

Incident C
Time: 14:45
Description: Worker reported a liquid splash on their hand. The affected skin has turned white and feels numb to the touch (anesthetic effect), rather than painful.

INSTRUCTIONS:
Identify the chemical responsible for each incident. Save your findings to /home/ga/Documents/exposure_diagnosis_report.txt.
EOF

# Set permissions
chown ga:ga /home/ga/Desktop/incident_reports.txt
chmod 644 /home/ga/Desktop/incident_reports.txt

# Launch Firefox to CAMEO Chemicals homepage
echo "Launching Firefox..."
launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga" 60

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="