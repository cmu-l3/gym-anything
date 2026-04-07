#!/bin/bash
set -euo pipefail

echo "=== Setting up professional_correspondence_formatting task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing Calligra instances
kill_calligra_processes
sleep 1

# Ensure directories exist
install -d -o ga -g ga /home/ga/Documents

# Create the unformatted correspondence document using Python + odfpy
cat > /tmp/create_correspondence.py << 'PYEOF'
#!/usr/bin/env python3
"""Create an unformatted .odt with three business letters as plain text."""

from odf.opendocument import OpenDocumentText
from odf.text import P
from odf import teletype

doc = OpenDocumentText()

letters = [
    # Letter 1: Lease Renewal Notice
    [
        "MERIDIAN PROPERTY GROUP",
        "1425 Commerce Boulevard, Suite 300",
        "Nashville, TN 37203",
        "Phone: (615) 555-0142",
        "",
        "October 15, 2025",
        "",
        "Mr. David Richardson",
        "Blackwood & Associates LLC",
        "850 Market Street, Suite 210",
        "Nashville, TN 37219",
        "",
        "RE: Lease Renewal - Suite 210, Riverview Commerce Center",
        "",
        "Dear Mr. Richardson:",
        "",
        "I am writing to inform you that your current commercial lease agreement for Suite 210 at Riverview Commerce Center is scheduled to expire on January 31, 2026. As a valued tenant, we would like to extend an early renewal offer for your consideration.",
        "",
        "Over the past three years, Blackwood & Associates has been an exemplary tenant, and we sincerely hope to continue our professional relationship. We are pleased to offer a five-year renewal term commencing February 1, 2026, at a monthly rate of $4,850, representing a modest 3.2% annual adjustment consistent with current market conditions in the Nashville metropolitan commercial real estate market.",
        "",
        "The renewal terms include continued access to all common areas, conference facilities, and the shared reception services on the second floor. Additionally, we have allocated funds in our 2026 capital improvement budget for upgrading the HVAC system serving the east wing, which will directly benefit your suite with improved climate control and energy efficiency.",
        "",
        "Please review the enclosed renewal agreement at your earliest convenience. We kindly request your signed response by November 30, 2025, to ensure uninterrupted occupancy. Should you wish to discuss any terms or schedule a walkthrough of the planned improvements, please do not hesitate to contact our leasing office directly.",
        "",
        "We look forward to continuing this productive tenancy for years to come.",
        "",
        "Sincerely,",
        "",
        "James K. Whitfield",
        "Senior Property Manager",
        "Meridian Property Group",
    ],
    # Letter 2: Maintenance Completion Notification
    [
        "MERIDIAN PROPERTY GROUP",
        "1425 Commerce Boulevard, Suite 300",
        "Nashville, TN 37203",
        "Phone: (615) 555-0142",
        "",
        "October 18, 2025",
        "",
        "Ms. Patricia Hensley",
        "2847 Elmwood Drive, Apt 4B",
        "Nashville, TN 37211",
        "",
        "RE: Completion of Maintenance Request #MR-2025-0847",
        "",
        "Dear Ms. Hensley:",
        "",
        "We are pleased to inform you that the maintenance work associated with your service request #MR-2025-0847, submitted on October 7, 2025, has been completed as of October 17, 2025.",
        "",
        "Our licensed HVAC technician from Cumberland Mechanical Services conducted a thorough inspection of the heating and cooling system serving your apartment. The technician identified a failed compressor capacitor and a refrigerant leak at the service valve connection. Both issues have been fully repaired, and the system has been recharged to manufacturer specifications. A new air filter has also been installed at no additional charge.",
        "",
        "The total cost of repairs has been covered under the terms of your lease agreement, and no charges will be applied to your account. The repaired system has been tested and is operating within normal parameters. You should notice improved cooling performance and reduced operational noise.",
        "",
        "If you experience any further issues with the HVAC system or any other aspect of your apartment, please submit a new maintenance request through our online tenant portal at portal.meridianpg.com or by calling our maintenance hotline at (615) 555-0199. We strive to address all non-emergency requests within five business days.",
        "",
        "Thank you for your patience during the repair process, and we apologize for any inconvenience caused by the temporary loss of climate control.",
        "",
        "Sincerely,",
        "",
        "Angela M. Torres",
        "Residential Maintenance Coordinator",
        "Meridian Property Group",
    ],
    # Letter 3: Vendor Contract Termination
    [
        "MERIDIAN PROPERTY GROUP",
        "1425 Commerce Boulevard, Suite 300",
        "Nashville, TN 37203",
        "Phone: (615) 555-0142",
        "",
        "October 20, 2025",
        "",
        "Mr. Robert Chalmers",
        "GreenScape Professional Services",
        "1100 Industrial Park Drive",
        "Murfreesboro, TN 37130",
        "",
        "RE: Termination of Landscaping Services Agreement (Contract #LSA-2023-044)",
        "",
        "Dear Mr. Chalmers:",
        "",
        "This letter serves as formal written notice of Meridian Property Group's intent to terminate the Landscaping Services Agreement, Contract #LSA-2023-044, effective November 20, 2025, in accordance with the thirty-day termination provision outlined in Section 8.2 of the agreement.",
        "",
        "Over the past several months, our property inspection team has documented recurring deficiencies in service delivery across multiple managed properties. Specifically, the October 2025 quarterly review identified the following unresolved issues: incomplete mowing at Riverview Commerce Center on three consecutive service visits, failure to apply the contracted fall fertilization treatment at Elmwood Residential Complex, and persistent accumulation of debris along the perimeter beds at Cumberland Office Park despite repeated requests for remediation.",
        "",
        "These deficiencies were formally communicated to your operations manager, Ms. Linda Beckett, via written correspondence on August 14, 2025, and again on September 22, 2025. While we acknowledge the partial improvements observed at Cumberland Office Park in early October, the overall pattern of service delivery has not met the standards established in our agreement.",
        "",
        "We request that GreenScape complete all outstanding scheduled services through November 20, 2025, including the fall leaf removal at all three properties. Final payment for services rendered through the termination date will be processed within thirty days of receipt of your final invoice, subject to verification by our property inspection team.",
        "",
        "Please arrange for the retrieval of any GreenScape equipment stored on our properties by November 25, 2025. Our facilities team will coordinate access at mutually convenient times.",
        "",
        "We appreciate the services GreenScape has provided over the past two years and wish your organization continued success.",
        "",
        "Sincerely,",
        "",
        "James K. Whitfield",
        "Senior Property Manager",
        "Meridian Property Group",
    ],
]

for letter_idx, letter_lines in enumerate(letters):
    for line in letter_lines:
        p = P()
        if line:
            teletype.addTextToElement(p, line)
        doc.text.addElement(p)
    # Add extra blank lines between letters (no page break — agent must add them)
    if letter_idx < len(letters) - 1:
        for _ in range(3):
            doc.text.addElement(P())

doc.save("/home/ga/Documents/meridian_correspondence.odt")
print("Document created successfully.")
PYEOF

python3 /tmp/create_correspondence.py

# Record baseline character count for anti-gaming
python3 -c "
from odf.opendocument import load
from odf import teletype
import sys
try:
    doc = load('/home/ga/Documents/meridian_correspondence.odt')
    text = teletype.extractText(doc.text)
    print(len(text))
except Exception as e:
    print(5000)
" > /tmp/baseline_char_count.txt 2>/dev/null || echo "5000" > /tmp/baseline_char_count.txt

chown ga:ga /home/ga/Documents/meridian_correspondence.odt

# Launch Calligra Words with the document
launch_calligra_document "/home/ga/Documents/meridian_correspondence.odt"
sleep 3

# Wait for window
wait_for_window "meridian_correspondence\|Calligra Words\|calligrawords" 30

# Maximize and focus
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 0.5
    focus_window "$WID"
fi

# Dismiss any dialogs
safe_xdotool ga :1 key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="