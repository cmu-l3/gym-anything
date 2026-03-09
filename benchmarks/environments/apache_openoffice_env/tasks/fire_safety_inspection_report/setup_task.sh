#!/bin/bash
# Setup script for fire_safety_inspection_report
set -e

echo "=== Setting up Fire Safety Inspection Report Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# 2. Clean up any previous run artifacts
rm -f /home/ga/Documents/FSI_Report_Glenwood_2024.odt 2>/dev/null || true
rm -f /home/ga/Documents/inspection_data.json 2>/dev/null || true

# 3. Create the input JSON data file
cat > /home/ga/Documents/inspection_data.json << 'JSONEOF'
{
  "report_metadata": {
    "report_number": "FPB-INS-2024-0847",
    "report_title": "Annual Fire Safety Inspection Report",
    "inspection_date": "2024-11-14",
    "compliance_deadline": "2025-02-14",
    "applicable_codes": ["NFPA 1", "NFPA 101", "NFPA 72", "NFPA 13", "NFPA 25", "425 ILCS 25"]
  },
  "inspector": {
    "name": "Captain Luis Restrepo",
    "title": "Fire Prevention Officer",
    "department": "Glenwood Fire Prevention Bureau",
    "license": "IL CFI License #F-2019-04821",
    "phone": "(708) 555-0193",
    "email": "l.restrepo@glenwoodfire.gov"
  },
  "facility": {
    "name": "Glenwood Community College District",
    "address": "18800 South Halsted Street, Glenwood, IL 60425",
    "contact_name": "Dr. Patricia Huang",
    "contact_title": "Vice President of Administrative Services",
    "contact_phone": "(708) 555-0274",
    "total_buildings": 5,
    "total_campus_sqft": 188500,
    "student_enrollment": 6842
  },
  "buildings": [
    {
      "id": "A",
      "name": "Main Academic Hall",
      "year_built": 1978,
      "sqft": 62000,
      "stories": 3,
      "occupancy_type": "Educational (NFPA 101 Ch. 14/15)",
      "compliance_score": 78,
      "overall_status": "Conditional Pass — Corrective Actions Required",
      "violations": [
        {
          "id": "V-A01",
          "code_ref": "NFPA 101 §7.1.10.1",
          "description": "North stairwell emergency exit door (Door N-103) blocked by stored furniture and AV equipment carts. Exit path obstructed to less than 28 inches clear width.",
          "severity": "Critical",
          "corrective_action": "Remove all obstructions immediately. Ensure minimum 44-inch clear width per NFPA 101 §7.3.4.1. Post 'KEEP CLEAR' signage.",
          "deadline": "2024-11-21"
        },
        {
          "id": "V-A02",
          "code_ref": "NFPA 10 §7.3.2",
          "description": "12 of 38 portable fire extinguishers past annual inspection date. Oldest expiration: March 2023. Located across all three floors.",
          "severity": "High",
          "corrective_action": "Schedule immediate inspection and servicing of all expired units by licensed contractor. Replace any units failing hydrostatic test.",
          "deadline": "2024-12-14"
        },
        {
          "id": "V-A03",
          "code_ref": "NFPA 72 §14.4.3.2",
          "description": "Third floor smoke detectors in rooms 310, 312, and 315 showed 'dirty' status during panel review. Sensitivity readings outside listed range.",
          "severity": "Moderate",
          "corrective_action": "Clean or replace affected smoke detectors. Perform sensitivity testing per NFPA 72 §14.4.3.2 and document results.",
          "deadline": "2025-01-14"
        },
        {
          "id": "V-A04",
          "code_ref": "NFPA 101 §7.10.1.2.1",
          "description": "Exit sign in second floor east corridor (near Room 225) non-illuminated. Battery backup failed during test.",
          "severity": "Moderate",
          "corrective_action": "Replace exit sign unit or repair battery backup. Verify minimum 90-minute emergency illumination per NFPA 101 §7.9.2.3.",
          "deadline": "2025-01-14"
        }
      ]
    },
    {
      "id": "B",
      "name": "Science & Technology Center",
      "year_built": 2004,
      "sqft": 38500,
      "stories": 2,
      "occupancy_type": "Educational / Laboratory (NFPA 45)",
      "compliance_score": 82,
      "overall_status": "Conditional Pass — Corrective Actions Required",
      "violations": [
        {
          "id": "V-B01",
          "code_ref": "NFPA 45 §10.3.2",
          "description": "Chemistry lab (Room 118) has flammable solvent containers stored within 36 inches of Bunsen burner stations. Incompatible storage with ignition sources.",
          "severity": "Critical",
          "corrective_action": "Relocate flammable solvents to approved flammable storage cabinet at least 20 feet from ignition sources per NFPA 45 §10.3.2. Retrain lab staff on storage protocols.",
          "deadline": "2024-11-21"
        },
        {
          "id": "V-B02",
          "code_ref": "NFPA 30 §9.5.1",
          "description": "Chemical storage room (Room B-004) flammable liquid cabinet not self-closing. Door latch mechanism broken — observed door propped open.",
          "severity": "High",
          "corrective_action": "Repair or replace self-closing mechanism on flammable storage cabinet. Doors must be self-closing and self-latching per NFPA 30.",
          "deadline": "2024-12-14"
        },
        {
          "id": "V-B03",
          "code_ref": "NFPA 101 §7.7.1",
          "description": "Second floor corridor near Room 210 has extension cords used as permanent wiring for 4 laptop charging stations. Cord running under carpet.",
          "severity": "Moderate",
          "corrective_action": "Install permanent receptacle outlets for charging stations. Remove extension cords used as permanent wiring per NFPA 101 §11.1.6.",
          "deadline": "2025-01-14"
        }
      ]
    },
    {
      "id": "C",
      "name": "Student Services Center",
      "year_built": 1985,
      "sqft": 28000,
      "stories": 2,
      "occupancy_type": "Business (NFPA 101 Ch. 38/39)",
      "compliance_score": 91,
      "overall_status": "Pass — Minor Corrective Actions",
      "violations": [
        {
          "id": "V-C01",
          "code_ref": "NFPA 101 §7.10.5.2.1",
          "description": "Two externally illuminated exit signs on first floor (main lobby and south corridor) have faded or illegible lettering. Letters do not meet minimum 6-inch height contrast requirement.",
          "severity": "Low",
          "corrective_action": "Replace exit sign face plates or entire units. Ensure lettering meets NFPA 101 §7.10.1.5.1 minimum 6-inch letter height with high-contrast background.",
          "deadline": "2025-02-14"
        },
        {
          "id": "V-C02",
          "code_ref": "NFPA 25 §5.2.5",
          "description": "Sprinkler system 5-year internal inspection due date was October 2023. No documentation of completed inspection on file.",
          "severity": "Moderate",
          "corrective_action": "Schedule and complete internal pipe inspection per NFPA 25 §5.2.5 within 30 days. Provide documentation to Fire Prevention Bureau.",
          "deadline": "2024-12-14"
        }
      ]
    },
    {
      "id": "D",
      "name": "Performing Arts Center",
      "year_built": 2011,
      "sqft": 44200,
      "stories": 2,
      "occupancy_type": "Assembly (NFPA 101 Ch. 12/13)",
      "compliance_score": 76,
      "overall_status": "Conditional Pass — Corrective Actions Required",
      "violations": [
        {
          "id": "V-D01",
          "code_ref": "NFPA 101 §12.1.7.1",
          "description": "Main auditorium (Capacity: 850) had 912 chairs set for November 8 event 'Fall Jazz Concert.' Seating arrangement exceeds posted maximum occupancy by 62 persons (7.3% over).",
          "severity": "Critical",
          "corrective_action": "Immediately reconfigure seating to not exceed 850 posted occupancy. Implement pre-event occupancy verification checklist. Designate crowd manager per NFPA 101 §12.7.6.",
          "deadline": "2024-11-21"
        },
        {
          "id": "V-D02",
          "code_ref": "NFPA 101 §12.2.3.6.3",
          "description": "Stage left emergency exit (Door D-SL2) has panic hardware with excessive operating force. Measured 22 lbs to initiate — exceeds 15 lb maximum per NFPA 101 §7.2.1.5.8.",
          "severity": "High",
          "corrective_action": "Repair or replace panic hardware on Door D-SL2. Maximum 15 lbs operating force to release latch. Retest and document.",
          "deadline": "2024-12-14"
        },
        {
          "id": "V-D03",
          "code_ref": "NFPA 101 §12.4.1",
          "description": "Backstage storage area contains theatrical scenery flats leaning against electrical panel room door, obstructing access. Combustible materials within 3 feet of electrical panel.",
          "severity": "High",
          "corrective_action": "Clear all combustible materials from within 36 inches of electrical panels per NEC 110.26. Establish designated storage area for scenery flats away from electrical equipment.",
          "deadline": "2024-12-14"
        }
      ]
    },
    {
      "id": "E",
      "name": "Physical Plant / Maintenance Building",
      "year_built": 1982,
      "sqft": 15800,
      "stories": 1,
      "occupancy_type": "Industrial / Storage (NFPA 101 Ch. 40/42)",
      "compliance_score": 64,
      "overall_status": "Fail — Critical Deficiencies",
      "violations": [
        {
          "id": "V-E01",
          "code_ref": "NFPA 25 §15.5.2",
          "description": "Sprinkler system Zone 3 (paint storage and workshop area, approx. 4,200 sqft) has been out of service since August 2024 due to a reported 'leak under investigation.' No fire watch implemented. No impairment tag on riser.",
          "severity": "Critical",
          "corrective_action": "Restore Zone 3 sprinkler system to service immediately or implement compliant fire watch per NFPA 25 §15.5. File Impairment Notice with Fire Prevention Bureau within 4 hours of receipt of this report.",
          "deadline": "2024-11-15"
        },
        {
          "id": "V-E02",
          "code_ref": "NFPA 30 §9.4.1",
          "description": "Paint storage room contains approximately 85 gallons of flammable and combustible liquids stored in non-approved containers and on open wooden shelving. Exceeds maximum allowable quantities for non-sprinklered area.",
          "severity": "Critical",
          "corrective_action": "Transfer all flammable/combustible liquids to approved flammable storage cabinets per NFPA 30 Chapter 9. Reduce quantities to MAQ for unsprinklered storage or restore sprinkler coverage first.",
          "deadline": "2024-11-21"
        },
        {
          "id": "V-E03",
          "code_ref": "NFPA 1 §11.1.6",
          "description": "Main workshop area has multiple extension cords and multi-outlet adapters used as permanent wiring for power tools and equipment. Several cords show visible damage (fraying, exposed conductors).",
          "severity": "High",
          "corrective_action": "Remove all damaged cords immediately. Install permanent receptacle outlets for tools and equipment. Extension cords shall not be used as a substitute for permanent wiring.",
          "deadline": "2024-12-14"
        },
        {
          "id": "V-E04",
          "code_ref": "NFPA 101 §42.7.2.1",
          "description": "No posted evacuation plan or emergency action plan visible in any area of the building. Employees interviewed could not describe evacuation routes.",
          "severity": "High",
          "corrective_action": "Develop and post evacuation floor plans at all building exits and common areas. Conduct evacuation drill within 30 days. Document training per NFPA 101 §4.7.2.1.",
          "deadline": "2024-12-14"
        },
        {
          "id": "V-E05",
          "code_ref": "NFPA 72 §14.4.5.3",
          "description": "Fire alarm control panel (Fire-Lite MS-9600) showing 3 active supervisory signals and 1 trouble signal. Oldest trouble condition logged October 2, 2024 — unresolved for 43 days.",
          "severity": "Moderate",
          "corrective_action": "Investigate and clear all trouble and supervisory conditions on FACP. Document resolution of each condition. Ensure monitoring company receives clear signals.",
          "deadline": "2025-01-14"
        }
      ]
    }
  ]
}
JSONEOF
chown ga:ga /home/ga/Documents/inspection_data.json
chmod 644 /home/ga/Documents/inspection_data.json

# 4. Prepare OpenOffice environment (Shortcut)
mkdir -p /home/ga/Desktop
if [ -x "/opt/openoffice4/program/soffice" ]; then
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

# 5. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_exists

# 6. Launch OpenOffice Writer to ensure it's ready for the agent
# The agent is expected to create a NEW document, but having the app open helps
if ! pgrep -f "soffice" > /dev/null 2>&1; then
    echo "Launching OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    sleep 5
fi

# 7. Maximize window
DISPLAY=:1 wmctrl -r "OpenOffice" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Input: /home/ga/Documents/inspection_data.json"
echo "Output Target: /home/ga/Documents/FSI_Report_Glenwood_2024.odt"