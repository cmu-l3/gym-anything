#!/bin/bash
echo "=== Setting up flatten_vitals_to_csv task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory does NOT exist (agent should handle creation or it's created by Mirth)
# Actually, creating it for the agent reduces permission friction, but description says "output directory... must be created".
# We'll clean it up to ensure fresh state.
rm -rf /tmp/research_data

# Create a sample HL7 message for the agent to use
cat > /home/ga/sample_vitals.hl7 <<EOF
MSH|^~\&|MONITOR|ICU|NEXTGEN|HIS|202403151000||ORU^R01|MSG001|P|2.5
PID|1||12345^^^MRN||DOE^JOHN||19800101|M
OBR|1|||VITAL_SIGNS|||202403150955
OBX|1|NM|8867-4^Heart Rate||80|bpm
OBX|2|NM|8480-6^Systolic BP||120|mm[Hg]
OBX|3|NM|8462-4^Diastolic BP||80|mm[Hg]
OBX|4|NM|2708-6^Oxygen Saturation||98|%
OBX|5|NM|9999-9^Irrelevant Lab||5.5|mmol/L
EOF
chown ga:ga /home/ga/sample_vitals.hl7

# Wait for NextGen Connect to be ready
wait_for_api 120

# Open terminal with context
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "======================================================="
echo " Task: Flatten HL7 Vitals to CSV"
echo "======================================================="
echo "Goal: Create a channel that converts HL7 ORU messages"
echo "      to a flat CSV format."
echo ""
echo "Input: TCP Port 6661 (HL7 v2.x)"
echo "Output: Append to /tmp/research_data/vitals.csv"
echo ""
echo "Required Columns:"
echo "PatientID, ObservationTime, HR, SysBP, DiaBP, SpO2"
echo ""
echo "LOINC Codes to Extract:"
echo "  Heart Rate:   8867-4"
echo "  Systolic BP:  8480-6"
echo "  Diastolic BP: 8462-4"
echo "  SpO2:         2708-6"
echo ""
echo "Sample message: /home/ga/sample_vitals.hl7"
echo ""
echo "Tools:"
echo "  - Mirth Administrator (Firefox)"
echo "  - nc localhost 6661 < /home/ga/sample_vitals.hl7"
echo "======================================================="
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="