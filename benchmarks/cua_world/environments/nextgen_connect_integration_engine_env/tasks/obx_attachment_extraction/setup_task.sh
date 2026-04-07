#!/bin/bash
set -e
echo "=== Setting up OBX Attachment Extraction Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Create output directory
mkdir -p /home/ga/lab_reports
chmod 777 /home/ga/lab_reports
chown ga:ga /home/ga/lab_reports

# Create test data directory
mkdir -p /home/ga/test_data
chown ga:ga /home/ga/test_data

# Generate a valid PDF and embed it in an HL7 message using Python
# We do this to ensure we have a real, decodable PDF for verification
python3 -c '
import base64
import os

# Minimal valid PDF content
pdf_content = (
    b"%PDF-1.1\n"
    b"1 0 obj\n"
    b"<< /Type /Catalog /Pages 2 0 R >>\n"
    b"endobj\n"
    b"2 0 obj\n"
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>\n"
    b"endobj\n"
    b"3 0 obj\n"
    b"<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> /MediaBox [0 0 300 144] /Contents 5 0 R >>\n"
    b"endobj\n"
    b"4 0 obj\n"
    b"<< /Type /Font /Subtype /Type1 /Name /F1 /BaseFont /Helvetica >>\n"
    b"endobj\n"
    b"5 0 obj\n"
    b"<< /Length 55 >>\n"
    b"stream\n"
    b"BT /F1 24 Tf 10 100 Td (Lab Report for PAT78432) Tj ET\n"
    b"endstream\n"
    b"endobj\n"
    b"xref\n"
    b"0 6\n"
    b"0000000000 65535 f \n"
    b"0000000010 00000 n \n"
    b"0000000060 00000 n \n"
    b"0000000117 00000 n \n"
    b"0000000238 00000 n \n"
    b"0000000325 00000 n \n"
    b"trailer\n"
    b"<< /Size 6 /Root 1 0 R >>\n"
    b"startxref\n"
    b"430\n"
    b"%%EOF"
)

# Save the raw PDF for ground truth verification (hidden from agent)
with open("/tmp/ground_truth.pdf", "wb") as f:
    f.write(pdf_content)

# Base64 encode
b64_pdf = base64.b64encode(pdf_content).decode("utf-8")

# Construct HL7 message
hl7_msg = (
    f"MSH|^~\\&|LABSYS|REFLAB|EHR|MEMORIAL_HOSP|20240115120000||ORU^R01|MSG00001|P|2.3\r"
    f"PID|1||PAT78432^^^HOSP^MR||SMITH^JANE^A||19780515|F|||123 OAK ST^^BOSTON^MA^02101\r"
    f"PBR|1||ACC98765|24317-0^Hemogram panel^LN|||20240115080000\r"
    f"OBX|1|ED|PDF^Lab Report^L||^application^pdf^Base64^{b64_pdf}||||||F\r"
)

with open("/home/ga/test_data/test_oru_message.hl7", "w") as f:
    f.write(hl7_msg)

print("Test HL7 message generated.")
'

# Set permissions for test data
chown ga:ga /home/ga/test_data/test_oru_message.hl7
chmod 644 /home/ga/test_data/test_oru_message.hl7

# Wait for NextGen Connect API to be ready
echo "Waiting for NextGen Connect API..."
wait_for_api 120

# Open a terminal for the agent
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "========================================================"
echo " NextGen Connect - OBX Attachment Extraction Task"
echo "========================================================"
echo ""
echo "GOAL: Create a channel to extract PDF reports from HL7 messages."
echo ""
echo "Channel Specifications:"
echo "  - Name: Lab_Report_Extractor"
echo "  - Source: TCP Listener on port 6661 (MLLP)"
echo "  - Logic: Extract Base64 PDF from OBX-5.5, decode to binary"
echo "  - Output: Write to /home/ga/lab_reports/"
echo "  - Filename: Must include MRN (PID-3.1), e.g., PAT78432.pdf"
echo ""
echo "Test Data:"
echo "  - /home/ga/test_data/test_oru_message.hl7"
echo ""
echo "Credentials (API/Web): admin / admin"
echo "API URL: https://localhost:8443/api"
echo ""
exec bash
' 2>/dev/null &

# Open Firefox to the landing page
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8080 &"
fi

# Ensure window focus
sleep 5
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="