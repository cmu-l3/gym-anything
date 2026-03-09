#!/bin/bash
set -e
echo "=== Setting up Policy Manual Adaptation Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Prepare Directories
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Desktop
# Clean up potential leftovers
rm -f /home/ga/Documents/maricopa_cd_response_manual.odt
rm -f /home/ga/Documents/azdhs_cd_response_manual.odt
rm -f /home/ga/Documents/adaptation_instructions.txt

# 2. Generate the Adaptation Instructions File
cat > /home/ga/Documents/adaptation_instructions.txt << 'EOF'
ADAPTATION INSTRUCTIONS
-----------------------
Source Document: azdhs_cd_response_manual.odt
Target Document: maricopa_cd_response_manual.odt

Please perform the following changes to adapt the State manual for County use:

1. FIND AND REPLACE (Case Sensitive):
   - Find: "Arizona Department of Health Services" -> Replace with: "Maricopa County Department of Public Health"
   - Find: "State Epidemiology and Response Division" -> Replace with: "County Epidemiology Unit"
   - Find: "(602) 555-0147" -> Replace with: "(602) 555-0328"
   - Find: "@azdhs.gov" -> Replace with: "@maricopa.gov"

2. FIX FORMATTING:
   The following sections lost their heading styles and appear as plain bold text.
   Apply "Heading 1" paragraph style to:
   - Section 3: "3. Outbreak Investigation Procedures"
   - Section 6: "6. Contact Tracing Operations"
   - Section 9: "9. Resource Management and Logistics"

3. INSERT PAGE HEADER:
   - Insert a standard Page Header.
   - Type "MARICOPA COUNTY – CONFIDENTIAL" in the header area.
   - Ensure it appears on all pages.

4. ADD REVISION HISTORY:
   - Go to the very end of the document.
   - Add a new Heading 1 titled "Revision History".
   - Insert a Table (4 columns, 2 rows) with headers: Version | Date | Author | Description.
   - Add row: "2.0" | "2025-01-15" | "Dr. Elena Sandoval-Cruz" | "Adapted for Maricopa County use".

5. SAVE:
   - Save the file as "maricopa_cd_response_manual.odt" in the Documents folder.
EOF
chown ga:ga /home/ga/Documents/adaptation_instructions.txt

# 3. Generate the Source ODT File (azdhs_cd_response_manual.odt)
# We use a python script to create a valid ODT with specific "bugs" (fake headings)
echo "Generating source ODT file..."
python3 -c '
import os
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties, MasterPage, PageLayout, PageLayoutProperties, Header
from odf.text import H, P, Span

doc = OpenDocumentText()

# --- Create Styles ---
# Standard Heading 1
s1 = Style(name="Heading 1", family="paragraph")
s1.addElement(TextProperties(attributes={"fontsize":"18pt","fontweight":"bold"}))
s1.addElement(ParagraphProperties(attributes={"marginbottom":"0.2cm", "margintop":"0.4cm"}))
doc.styles.addElement(s1)

# "Fake" Heading (just bold paragraph) - simulating broken formatting
s_fake = Style(name="FakeHeading", family="paragraph")
s_fake.addElement(TextProperties(attributes={"fontsize":"14pt","fontweight":"bold"}))
s_fake.addElement(ParagraphProperties(attributes={"marginbottom":"0.2cm", "margintop":"0.4cm"}))
doc.styles.addElement(s_fake)

# Standard Body Text
s_body = Style(name="Standard", family="paragraph")
s_body.addElement(TextProperties(attributes={"fontsize":"12pt"}))
doc.styles.addElement(s_body)

# --- Content Generation Helper ---
def add_section(title, content, is_broken=False):
    if is_broken:
        # Broken sections use P with fake style instead of H
        doc.text.addElement(P(stylename=s_fake, text=title))
    else:
        # Good sections use H with outline level
        doc.text.addElement(H(outlinelevel=1, stylename=s1, text=title))
    
    doc.text.addElement(P(stylename=s_body, text=content))
    doc.text.addElement(P(stylename=s_body, text="")) # spacer

# --- Document Content ---
intro_text = "The Arizona Department of Health Services (ADHS) is responsible for the coordination of communicable disease response across the state. This manual provides the operational framework for the State Epidemiology and Response Division when managing outbreaks."
add_section("1. Purpose and Authority", intro_text)

surv_text = "All healthcare providers must report suspected cases of Class 1 agents immediately to the Arizona Department of Health Services. Reports should be made via the secure portal or by calling (602) 555-0147. Email reports to surveillance@azdhs.gov are also accepted for non-urgent queries."
add_section("2. Disease Surveillance and Mandatory Reporting", surv_text)

# BROKEN SECTION
outbreak_text = "Upon notification, the State Epidemiology and Response Division will deploy a field team. The primary objective is to characterize the outbreak by time, place, and person. Contact the duty officer at (602) 555-0147 for activation codes."
add_section("3. Outbreak Investigation Procedures", outbreak_text, is_broken=True)

iso_text = "Isolation orders are issued under the authority of the Arizona Department of Health Services Director. See A.R.S. Title 36 for specific statutes."
add_section("4. Isolation and Quarantine Protocols", iso_text)

lab_text = "Specimens must be routed to the State Laboratory in Phoenix. Ensure chain of custody forms are emailed to lab_intake@azdhs.gov prior to courier dispatch."
add_section("5. Laboratory Testing Coordination", lab_text)

# BROKEN SECTION
contact_text = "Contact tracing is managed by the State Epidemiology and Response Division. Staff should interview confirmed cases within 24 hours. Use the ADHS standard interview form."
add_section("6. Contact Tracing Operations", contact_text, is_broken=True)

ic_text = "Healthcare facilities must implement immediate droplet precautions. The Arizona Department of Health Services Infection Prevention team will conduct site visits."
add_section("7. Infection Control in Healthcare Facilities", ic_text)

media_text = "All press inquiries should be directed to the Public Information Officer at pio@azdhs.gov. The Arizona Department of Health Services maintains a 24/7 media line."
add_section("8. Public Communication and Media Relations", media_text)

# BROKEN SECTION
logs_text = "Requests for the Strategic National Stockpile must be approved by the State Epidemiology and Response Division. Call logistics at (602) 555-0147 or email logistics@azdhs.gov."
add_section("9. Resource Management and Logistics", logs_text, is_broken=True)

aar_text = "An After-Action Report (AAR) must be filed within 30 days of deactivation. Submit findings to the Arizona Department of Health Services Preparedness Bureau."
add_section("10. Post-Event Review and After-Action Reporting", aar_text)

# Save
doc.save("/home/ga/Documents/azdhs_cd_response_manual.odt")
'

chown ga:ga /home/ga/Documents/azdhs_cd_response_manual.odt

# 4. Start OpenOffice Writer with the source file
echo "Launching OpenOffice Writer..."
# Use su - ga to run as user
su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer /home/ga/Documents/azdhs_cd_response_manual.odt" &

# 5. Wait for window and maximize
wait_for_window "OpenOffice Writer" 30
# Get window ID
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing window $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Record timestamp and snapshot
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="