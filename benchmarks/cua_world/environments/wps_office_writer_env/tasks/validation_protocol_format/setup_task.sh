#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Validation Protocol Format Task ==="

sudo -u ga mkdir -p /home/ga/Documents

# Record task start time
date +%s > /tmp/validation_protocol_format_start_ts

# Create the raw unformatted IQ protocol document
python3 << 'PYEOF'
from docx import Document

doc = Document()

# Add all text as plain, unstyled paragraphs
doc.add_paragraph("INSTALLATION QUALIFICATION PROTOCOL")
doc.add_paragraph("Protocol No: IQ-2024-HPLC-003")
doc.add_paragraph("Equipment: Agilent 1260 Infinity II HPLC")
doc.add_paragraph("Effective Date: 2024-11-15")
doc.add_paragraph("")

doc.add_paragraph("1.0 PURPOSE")
doc.add_paragraph("The purpose of this Installation Qualification (IQ) protocol is to provide documented evidence that the Agilent 1260 Infinity II HPLC system has been delivered, installed, and configured in accordance with the manufacturer's specifications and cGMP requirements.")
doc.add_paragraph("")

doc.add_paragraph("2.0 SCOPE")
doc.add_paragraph("This protocol applies to the Agilent 1260 Infinity II HPLC system installed in the Quality Control Laboratory, Room 402, Building B.")
doc.add_paragraph("")

doc.add_paragraph("3.0 RESPONSIBILITIES")
doc.add_paragraph("Validation Engineer: Prepare, execute, and summarize the IQ protocol. Quality Assurance: Review and approve the protocol and final report. System Owner: Ensure equipment is available for qualification.")
doc.add_paragraph("")

doc.add_paragraph("4.0 EQUIPMENT DESCRIPTION")
doc.add_paragraph("The system is a high-performance liquid chromatography instrument used for assay and impurity testing. Equipment Data to be verified during execution:")
doc.add_paragraph("Manufacturer: Agilent Technologies")
doc.add_paragraph("Model: 1260 Infinity II")
doc.add_paragraph("Serial Number: DE12345678")
doc.add_paragraph("Modules: Quaternary Pump (G7111B), Multisampler (G7167A), Multicolumn Thermostat (G7116A), Diode Array Detector (G7115A)")
doc.add_paragraph("Software Version: OpenLab CDS v2.5")
doc.add_paragraph("Location: QC Lab, Room 402")
doc.add_paragraph("")

doc.add_paragraph("5.0 REFERENCE DOCUMENTS")
doc.add_paragraph("Agilent 1260 Infinity II User Manual. Site SOP-VAL-005 (Equipment Qualification). 21 CFR Part 11 and Part 211.")
doc.add_paragraph("")

doc.add_paragraph("6.0 PREREQUISITES")
doc.add_paragraph("Prior to execution, ensure the system is physically placed on the designated bench and all electrical/network connections are available.")
doc.add_paragraph("")

doc.add_paragraph("7.0 INSTALLATION VERIFICATION")
doc.add_paragraph("The following test cases must be executed to verify proper installation.")
doc.add_paragraph("")

doc.add_paragraph("7.1 IQ-001: Equipment Delivery Verification")
doc.add_paragraph("Test ID: IQ-001")
doc.add_paragraph("Description: Verify that the delivered equipment matches the purchase order and packing slip.")
doc.add_paragraph("Acceptance Criteria: All components listed on PO #88472 are present and undamaged.")
doc.add_paragraph("Method: Visual inspection and documentation comparison.")
doc.add_paragraph("Expected Result: Components match PO exactly with no physical damage.")
doc.add_paragraph("")

doc.add_paragraph("7.2 IQ-002: Equipment Identification")
doc.add_paragraph("Test ID: IQ-002")
doc.add_paragraph("Description: Record the model and serial numbers of all modules.")
doc.add_paragraph("Acceptance Criteria: Module details match the equipment description in Section 4.0.")
doc.add_paragraph("Method: Inspect the data plates on the rear of each module.")
doc.add_paragraph("Expected Result: All serial numbers are accurately recorded and match documentation.")
doc.add_paragraph("")

doc.add_paragraph("7.3 IQ-003: Utility and Facility Requirements")
doc.add_paragraph("Test ID: IQ-003")
doc.add_paragraph("Description: Verify that required utilities meet manufacturer specifications.")
doc.add_paragraph("Acceptance Criteria: Power supply is 100-240 VAC, 50/60 Hz. Network drop is active.")
doc.add_paragraph("Method: Use a calibrated multimeter to check voltage. Test network port.")
doc.add_paragraph("Expected Result: Voltage is within range and network is active.")
doc.add_paragraph("")

doc.add_paragraph("7.4 IQ-004: Software Installation Verification")
doc.add_paragraph("Test ID: IQ-004")
doc.add_paragraph("Description: Verify the installation of the chromatography data system.")
doc.add_paragraph("Acceptance Criteria: OpenLab CDS v2.5 is installed and launches without errors.")
doc.add_paragraph("Method: Turn on PC, log into Windows, launch OpenLab CDS.")
doc.add_paragraph("Expected Result: Software launches to the login screen with correct version displayed.")
doc.add_paragraph("")

doc.add_paragraph("7.5 IQ-005: Environmental Conditions")
doc.add_paragraph("Test ID: IQ-005")
doc.add_paragraph("Description: Verify the laboratory environment meets operating requirements.")
doc.add_paragraph("Acceptance Criteria: Temperature is 15-35 C, relative humidity is 20-80%.")
doc.add_paragraph("Method: Read the calibrated room environmental monitor.")
doc.add_paragraph("Expected Result: Lab conditions are within specified operating limits.")
doc.add_paragraph("")

doc.add_paragraph("7.6 IQ-006: Documentation and Certificates")
doc.add_paragraph("Test ID: IQ-006")
doc.add_paragraph("Description: Verify receipt of manufacturer documentation and calibration certificates.")
doc.add_paragraph("Acceptance Criteria: User manuals and Declaration of Conformity are present.")
doc.add_paragraph("Method: Review the documentation package provided with the instrument.")
doc.add_paragraph("Expected Result: All required manufacturer documents are filed with the protocol.")
doc.add_paragraph("")

doc.add_paragraph("8.0 ACCEPTANCE CRITERIA SUMMARY")
doc.add_paragraph("Provide a summary of all executed test cases from Section 7.0 here.")
doc.add_paragraph("")

doc.add_paragraph("9.0 DEVIATIONS")
doc.add_paragraph("Any discrepancies encountered during execution must be logged as deviations and resolved prior to final approval.")
doc.add_paragraph("")

doc.add_paragraph("10.0 APPROVAL")
doc.add_paragraph("By signing below, the reviewers and approvers certify that the equipment has been successfully installed and meets all acceptance criteria.")
doc.add_paragraph("Prepared By: [Name] [Title] [Signature] [Date]")
doc.add_paragraph("Reviewed By: [Name] [Title] [Signature] [Date]")
doc.add_paragraph("Approved By: [Name] [Title] [Signature] [Date]")

doc.save('/home/ga/Documents/iq_protocol_raw.docx')
PYEOF

sudo chown ga:ga /home/ga/Documents/iq_protocol_raw.docx

# Clean up any previous output files
rm -f /home/ga/Documents/iq_protocol_formatted.docx 2>/dev/null || true

# Launch WPS Writer with the document
echo "Launching WPS Writer..."
sudo -u ga DISPLAY=:1 wps /home/ga/Documents/iq_protocol_raw.docx > /dev/null 2>&1 &
sleep 6

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Focus and maximize the window
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 1

# Take initial screenshot
take_screenshot /tmp/validation_protocol_format_start_screenshot.png

echo "=== Task setup complete ==="