#!/bin/bash
# Setup script for audit_report_fix task
# Creates a facility condition assessment report draft with 4 formatting violations:
#   1. All 10 subsection headings at wrong level (H3 instead of H2)
#   2. Fake manual TOC (text:p elements, NOT text:table-of-content)
#   3. 3 paragraphs with red text (violates office policy: black-only body text)
#   4. No footer / no page numbers

echo "=== Setting up Audit Report Fix Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up any previous task artifacts
rm -f /home/ga/Documents/building_audit_draft.odt 2>/dev/null || true
rm -f /home/ga/Documents/building_audit_final.odt 2>/dev/null || true

python3 << 'PYEOF'
import zipfile
import os

OUTPUT_PATH = "/home/ga/Documents/building_audit_draft.odt"

MIMETYPE = "application/vnd.oasis.opendocument.text"

MANIFEST = """<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"
                   manifest:version="1.2">
  <manifest:file-entry manifest:full-path="/"
    manifest:media-type="application/vnd.oasis.opendocument.text"
    manifest:version="1.2"/>
  <manifest:file-entry manifest:full-path="content.xml"
    manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="styles.xml"
    manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="meta.xml"
    manifest:media-type="text/xml"/>
</manifest:manifest>"""

# styles.xml: NO footer definition (bug #4)
STYLES = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
  office:version="1.2">
  <office:styles>
    <style:default-style style:family="paragraph">
      <style:paragraph-properties fo:margin-top="0cm" fo:margin-bottom="0.212cm"
        fo:line-height="120%"/>
      <style:text-properties fo:font-size="11pt" fo:color="#000000"/>
    </style:default-style>
    <style:style style:name="Default_20_Paragraph_20_Style"
      style:display-name="Default Paragraph Style"
      style:family="paragraph" style:class="text">
      <style:text-properties fo:font-size="11pt"/>
    </style:style>
    <style:style style:name="Heading_20_1" style:display-name="Heading 1"
      style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style"
      style:class="text">
      <style:paragraph-properties fo:margin-top="0.4cm"
        fo:margin-bottom="0.2cm" fo:keep-with-next="always"/>
      <style:text-properties fo:font-size="15pt" fo:font-weight="bold"
        fo:color="#1F3864"/>
    </style:style>
    <style:style style:name="Heading_20_2" style:display-name="Heading 2"
      style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style"
      style:class="text">
      <style:paragraph-properties fo:margin-top="0.3cm"
        fo:margin-bottom="0.15cm" fo:keep-with-next="always"/>
      <style:text-properties fo:font-size="12pt" fo:font-weight="bold"
        fo:color="#000000"/>
    </style:style>
    <style:style style:name="Heading_20_3" style:display-name="Heading 3"
      style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style"
      style:class="text">
      <style:paragraph-properties fo:margin-top="0.25cm"
        fo:margin-bottom="0.12cm" fo:keep-with-next="always"/>
      <style:text-properties fo:font-size="11pt" fo:font-weight="bold"
        fo:font-style="italic" fo:color="#000000"/>
    </style:style>
    <style:style style:name="Title" style:display-name="Title"
      style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style"
      style:class="chapter">
      <style:paragraph-properties fo:text-align="center" fo:margin-bottom="0.3cm"/>
      <style:text-properties fo:font-size="18pt" fo:font-weight="bold"/>
    </style:style>
  </office:styles>
  <office:automatic-styles>
    <style:page-layout style:name="pm1">
      <style:page-layout-properties fo:page-width="21.59cm"
        fo:page-height="27.94cm" style:print-orientation="portrait"
        fo:margin-top="2.54cm" fo:margin-bottom="2.54cm"
        fo:margin-left="2.54cm" fo:margin-right="2.54cm"/>
      <!-- NOTE: No style:footer element — bug #4, no page numbers -->
    </style:page-layout>
  </office:automatic-styles>
  <office:master-styles>
    <style:master-page style:name="Standard"
      style:page-layout-name="pm1">
      <!-- No footer content — page numbers missing -->
    </style:master-page>
  </office:master-styles>
</office:document-styles>"""

META = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-meta
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0"
  office:version="1.2">
  <office:meta>
    <meta:creation-date>2024-11-04T08:30:00</meta:creation-date>
    <meta:initial-creator>External Inspector</meta:initial-creator>
  </office:meta>
</office:document-meta>"""

# content.xml helpers
def h1(text):
    return f'      <text:h text:outline-level="1">{text}</text:h>'

def h3_wrong(text):
    """Bug #1: subsection heading at level 3, should be level 2."""
    return f'      <text:h text:outline-level="3">{text}</text:h>'

def body(text):
    return f'      <text:p text:style-name="BodyText">{text}</text:p>'

def red_body(text):
    """Bug #3: paragraph with red text formatting, should be black."""
    return f'      <text:p text:style-name="RedDeficiency">{text}</text:p>'

def blank():
    return '      <text:p text:style-name="BodyText"/>'

# Bug #2: Fake manual TOC — just text:p elements, NOT text:table-of-content
fake_toc_lines = [
    '      <text:p text:style-name="TOCTitle">TABLE OF CONTENTS</text:p>',
    '      <text:p text:style-name="TOCEntry">1.  Executive Summary ................................................ 1</text:p>',
    '      <text:p text:style-name="TOCEntry">2.  Property Overview ................................................. 2</text:p>',
    '      <text:p text:style-name="TOCEntry">3.  Structural and Envelope Assessment ................................. 4</text:p>',
    '      <text:p text:style-name="TOCEntry">4.  Mechanical, Electrical, and Plumbing Systems ...................... 6</text:p>',
    '      <text:p text:style-name="TOCEntry">5.  Deficiencies and Recommendations ................................. 8</text:p>',
    '      <text:p text:style-name="TOCEntry">6.  Cost Estimate Summary ........................................... 10</text:p>',
    blank(),
]

sections = (
    fake_toc_lines
    + [
    # Title block
    '      <text:p text:style-name="Title">FACILITY CONDITION ASSESSMENT REPORT</text:p>',
    '      <text:p text:style-name="SubTitle">Howard Office Building — 700 2nd Avenue South, Nashville, TN 37210</text:p>',
    '      <text:p text:style-name="SubTitle">Metro Nashville Department of General Services</text:p>',
    '      <text:p text:style-name="SubTitle">Report No. FCA-2024-0117 | Inspection Date: November 4, 2024</text:p>',
    '      <text:p text:style-name="SubTitle">Prepared by: Patricia Holloway, Property Inspector IV</text:p>',
    blank(),

    # Section 1
    h1("1. EXECUTIVE SUMMARY"),
    h3_wrong("1.1 Assessment Overview"),  # BUG: should be H2
    body("This Facility Condition Assessment (FCA) was conducted on November 4, 2024, for the Howard Office Building located at 700 2nd Avenue South, Nashville, Tennessee 37210. The building is a six-story Class B office structure constructed in 1974 and owned by the Metropolitan Government of Nashville and Davidson County. The assessment encompasses all major building systems including structural, mechanical, electrical, plumbing, and envelope components."),
    body("The assessment methodology follows ASTM E2018-15 Property Condition Assessment guidelines combined with Metro Nashville Department of General Services Standard Operating Procedure DGS-FCA-003, Revision 2. Physical inspection was supplemented by review of available maintenance records, prior inspection reports, and mechanical drawings on file with the department."),
    blank(),
    h3_wrong("1.2 Critical Findings Summary"),  # BUG: should be H2
    body("The assessment identified seventeen (17) deficiency items across all building systems. Four deficiencies are classified as Immediate Action Items (Priority 1) requiring repair within 90 days. Eight deficiencies are classified as Priority 2 requiring repair within 12 months. Five deficiencies are categorized as Deferred Maintenance (Priority 3) addressable within a 3-5 year capital plan."),
    body("Total estimated repair costs for all identified deficiencies amount to $1,247,500, excluding soft costs and contingency. Immediate action items alone represent $318,000 in required expenditure. The building's overall condition is rated as Fair (3.2 on a 5-point scale), consistent with a structure of its age and maintenance history."),
    blank(),

    # Section 2
    h1("2. PROPERTY OVERVIEW"),
    h3_wrong("2.1 Building Identification"),  # BUG: should be H2
    body("The Howard Office Building, asset identifier MGN-OB-0117, is a 68,400 gross square foot, six-story office structure constructed in 1974. The building provides administrative office space for several Metro Nashville departments, currently housing approximately 340 employees across the Departments of Finance, Human Resources, and Codes Administration. The building sits on a 0.87-acre lot within the Metro Government office campus complex in downtown Nashville, Tennessee."),
    blank(),
    h3_wrong("2.2 Physical Characteristics"),  # BUG: should be H2
    body("Construction type: Reinforced concrete frame with brick veneer exterior and aluminum curtainwall window systems on the upper four floors. Floor-to-floor height averages 12 feet 4 inches. The building is fully air-conditioned and heated by a central plant serving the Metro campus. Original construction was completed by Hixson Architects and Engineers (Cincinnati, OH) under Metro contract 1972-C-0448. Significant capital improvements occurred in 1998 (HVAC retrofit), 2007 (roof replacement), and 2018 (elevator modernization)."),
    blank(),
    h3_wrong("2.3 Occupancy and Use Profile"),  # BUG: should be H2
    body("Current occupancy: approximately 95%. Normal operating hours are 7:00 AM to 6:00 PM, Monday through Friday. The building operates 52 weeks per year with reduced holiday staffing. Regulated systems include two elevators (Certificate No. NE-4417 and NE-4418), one fire suppression system (Metro Fire Permit FP-2024-0917), and a 2,400-gallon diesel emergency generator (Air Permit No. DEC-2019-1183)."),
    blank(),

    # Section 3
    h1("3. STRUCTURAL AND ENVELOPE ASSESSMENT"),
    h3_wrong("3.1 Foundation and Substructure"),  # BUG: should be H2
    body("Foundation system: reinforced concrete spread footings and grade beams bearing on native limestone. No evidence of foundation movement, differential settlement, or subsurface water intrusion was observed during inspection. Basement mechanical room walls display hairline shrinkage cracks typical of concrete of this age; cracks are non-structural and sealed. Floor slabs on grade in the basement utility areas show minor surface spalling in approximately 220 sq. ft. near the south loading dock; recommend surface repair during next scheduled maintenance cycle (Priority 3)."),
    blank(),
    h3_wrong("3.2 Structural Frame"),  # BUG: should be H2
    body("Reinforced concrete columns, beams, and floor slabs are in generally good condition. No evidence of section loss, chloride-induced corrosion, or structural cracking was identified. Exposed concrete at the 6th floor mechanical penthouse exhibits weathering and minor spalling at beam-to-column connections; recommend protective coating application (Priority 2, estimated $24,000). Structural drawings reviewed include original construction documents on file with Metro Archives (Drawing Set A-1974-117)."),
    blank(),
    h3_wrong("3.3 Exterior Facade and Windows"),  # BUG: should be H2
    body("Brick veneer on floors 1-2 shows moderate efflorescence on the north and west elevations. Tuckpointing is required in approximately 400 linear feet of mortar joints (Priority 2, estimated $28,500). The aluminum curtainwall system on floors 3-6 has reached the end of its design service life. Sealant at approximately 60% of glazing units has failed or is failing, creating potential water intrusion pathways. Full curtainwall sealant replacement is recommended (Priority 1, estimated $87,000). Two window units on the 5th floor north face have cracked glass requiring immediate replacement (Priority 1, estimated $4,200)."),
    blank(),

    # Section 4
    h1("4. MECHANICAL, ELECTRICAL, AND PLUMBING SYSTEMS"),
    h3_wrong("4.1 HVAC Systems"),  # BUG: should be H2
    body("The building's HVAC is served by the Metro Government central chilled water and steam plant via underground distribution. Building-side equipment includes four (4) air handling units (AHUs) installed during the 1998 retrofit, a cooling tower serving the computer room, and 47 variable air volume (VAV) terminal units. AHU-3 serving the 3rd floor south zone has a failed actuator on its heating coil valve (work order WO-2024-3871 open since September 2024); this unit is operating in manual override mode, creating energy waste and occupant discomfort. Repair recommended as Priority 1 (estimated $3,800)."),
    blank(),
    h3_wrong("4.2 Electrical Distribution and Lighting"),  # BUG: should be H2
    body("The main electrical service is rated 2,000A, 480/277V, 3-phase. Service entrance equipment is manufactured by Eaton (Cutler-Hammer) and is in serviceable condition. A thermal imaging scan performed October 28, 2024 (Metro Electrical Services contract) identified a hot connection at breaker panel LP-4B, 3rd floor electrical room, indicating a loose or corroded connection. This is classified as a fire hazard and is Priority 1 (estimated $1,200). Emergency lighting battery units: 11 of 38 units tested failed the 90-minute emergency lighting test; replacements required (Priority 2, estimated $8,800)."),
    blank(),
    h3_wrong("4.3 Plumbing and Fire Suppression"),  # BUG: should be H2
    body("Domestic water: supply and return piping is original galvanized steel on floors 1-3. Water analysis indicates iron levels at 0.42 mg/L, approaching the EPA secondary MCL of 0.3 mg/L. Piping replacement on floors 1-3 is recommended as part of a 5-year capital improvement plan (Priority 3, estimated $185,000). Floors 4-6 were re-piped with Type L copper in 2007 and remain serviceable. Fire suppression system is a wet-pipe sprinkler system last inspected by Metro Fire on March 14, 2024 with no deficiencies noted. All sprinkler heads within 24 inches of HVAC diffusers on the 6th floor should be inspected for obstruction per NFPA 25 requirements (Priority 3)."),
    blank(),

    # Section 5
    h1("5. DEFICIENCIES AND RECOMMENDATIONS"),
    h3_wrong("5.1 Immediate Action Items"),  # BUG: should be H2
    red_body("PRIORITY 1 — IMMEDIATE ACTION REQUIRED: Curtainwall sealant failure on floors 3-6. Active water intrusion at northeast corner, 4th floor. Water staining and drywall damage observed in office suite 412. Estimated repair cost: $87,000. Responsible party: DGS Capital Projects. Contractor solicitation required immediately — further delay will result in interior damage acceleration and potential mold development."),
    red_body("PRIORITY 1 — IMMEDIATE ACTION REQUIRED: Electrical hazard at panel LP-4B (3rd floor). Thermal anomaly detected at 210°F on main feed lug. Fire risk identified. Panel must be de-energized and repaired by licensed electrician before resuming normal operations. Estimated repair: $1,200. Emergency work order to be issued within 5 business days. DGS Facilities Operations contact: Roger Simms, (615) 862-7000."),
    red_body("PRIORITY 1 — IMMEDIATE ACTION REQUIRED: HVAC unit AHU-3 (3rd floor south zone) operating in manual override since September 2024. Chilled water valve frozen open; space cannot be cooled. Tenant complaints documented in FM system (WO-2024-3871). Parts on order but repair has not been scheduled. This must be escalated to complete repair within 30 days. Estimated cost: $3,800."),
    blank(),
    h3_wrong("5.2 12-Month Capital Repair Plan"),  # BUG: should be H2
    body("The following deficiencies are classified as Priority 2 requiring completion within 12 months: (a) Structural frame protective coating at 6th floor penthouse ($24,000); (b) Brick veneer tuckpointing, north and west elevations ($28,500); (c) Emergency lighting battery replacement — 11 units ($8,800); (d) Roof membrane repairs at perimeter flashing — 280 linear feet ($19,500); (e) Interior corridor ceiling tile replacement — water-stained tiles throughout floors 3, 4, and 5 following window leakage ($14,200); (f) HVAC controls upgrade for BAS integration, 4th and 5th floors ($67,000); (g) ADA door hardware replacements in 3rd floor restrooms ($6,900); (h) Parking structure crack sealing and joint repair ($22,000). Subtotal Priority 2: $190,900."),
    blank(),

    # Section 6
    h1("6. COST ESTIMATE SUMMARY"),
    h3_wrong("6.1 Repair Cost Matrix"),  # BUG: should be H2
    body("Summary of estimated repair costs by priority and system category:"),
    body("Priority 1 (Immediate — within 90 days): Curtainwall sealant $87,000; Electrical panel repair $1,200; 5th floor window glass $4,200; AHU-3 valve/actuator $3,800. Priority 1 Subtotal: $96,200."),
    body("Priority 2 (12-month capital plan): Structural/envelope work $72,000; MEP systems $121,900. Priority 2 Subtotal: $193,900."),
    body("Priority 3 (Deferred maintenance, 3-5 year plan): Plumbing re-pipe floors 1-3 $185,000; Sprinkler head relocations $12,400; Parking structure Phase 2 $38,000; Basement slab repairs $7,800; Roof system replacement (full, year 5) $520,000. Priority 3 Subtotal: $763,200."),
    body("TOTAL ALL PRIORITIES (excluding soft costs and 15% contingency): $1,053,300. With soft costs and contingency: estimated $1,247,500."),
    blank(),
    h3_wrong("6.2 Funding Recommendations"),  # BUG: should be H2
    body("Priority 1 items totaling $96,200 should be funded from the DGS Emergency Repair Reserve Fund (account 10010-4420-48700). Priority 2 items totaling $193,900 should be included in the FY2025-2026 Capital Improvement Program budget request. The Inspector recommends that Priority 2 items be submitted to the Metro Budget Office by December 15, 2024 to meet the CIP submission deadline. Priority 3 items should be incorporated into the 5-year Facilities Capital Plan update scheduled for Spring 2025."),
    blank(),
    body("Inspector Signature: Patricia Holloway, Property Inspector IV, Metro Nashville Dept. of General Services"),
    body("Date of Report: November 4, 2024"),
    body("Report Reference: FCA-2024-0117"),
    body("This report is subject to review and approval by the Director of Facilities Management prior to official filing."),
    ]
)

# Automatic styles needed in content.xml
AUTO_STYLES = """  <office:automatic-styles>
    <!-- Bug #3: RedDeficiency style — body text with red color (fo:color="#ff0000")
         Office policy requires all body text to be black (fo:color="#000000") -->
    <style:style style:name="RedDeficiency" style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style">
      <style:paragraph-properties fo:margin-top="0cm" fo:margin-bottom="0.2cm"
        fo:text-align="justify"/>
      <style:text-properties fo:font-size="11pt" fo:font-weight="bold"
        fo:color="#ff0000"/>
    </style:style>
    <style:style style:name="BodyText" style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style">
      <style:paragraph-properties fo:margin-top="0cm" fo:margin-bottom="0.2cm"
        fo:text-align="justify"/>
      <style:text-properties fo:font-size="11pt" fo:color="#000000"/>
    </style:style>
    <style:style style:name="TOCTitle" style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style">
      <style:paragraph-properties fo:text-align="center" fo:margin-bottom="0.3cm"/>
      <style:text-properties fo:font-size="13pt" fo:font-weight="bold" fo:color="#000000"/>
    </style:style>
    <style:style style:name="TOCEntry" style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style">
      <style:paragraph-properties fo:margin-left="0.5cm" fo:margin-bottom="0.1cm"/>
      <style:text-properties fo:font-size="11pt" fo:color="#000000"/>
    </style:style>
    <style:style style:name="SubTitle" style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style">
      <style:paragraph-properties fo:text-align="center" fo:margin-bottom="0.15cm"/>
      <style:text-properties fo:font-size="12pt" fo:color="#000000"/>
    </style:style>
  </office:automatic-styles>"""

CONTENT = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
  xmlns:dc="http://purl.org/dc/elements/1.1/"
  office:version="1.2">
""" + AUTO_STYLES + """
  <office:body>
    <office:text>
""" + "\n".join(sections) + """
    </office:text>
  </office:body>
</office:document-content>"""

os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

with zipfile.ZipFile(OUTPUT_PATH, 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr(zipfile.ZipInfo('mimetype'), MIMETYPE)
    zf.writestr('META-INF/manifest.xml', MANIFEST)
    zf.writestr('content.xml', CONTENT)
    zf.writestr('styles.xml', STYLES)
    zf.writestr('meta.xml', META)

size = os.path.getsize(OUTPUT_PATH)
print(f"Created {OUTPUT_PATH} ({size} bytes)")

# Verify the bugs are present
import zipfile as zf2, re
with zf2.ZipFile(OUTPUT_PATH) as z:
    content_check = z.read('content.xml').decode('utf-8')
    styles_check = z.read('styles.xml').decode('utf-8')

h3_count = len(re.findall(r'text:outline-level="3"', content_check))
h2_count = len(re.findall(r'text:outline-level="2"', content_check))
red_count = len(re.findall(r'fo:color="#ff0000"', content_check))
has_fake_toc = 'TOCEntry' in content_check
has_real_toc = 'text:table-of-content' in content_check
has_footer = 'style:footer' in styles_check
print(f"Verification: H3={h3_count} (expected 10), H2={h2_count} (expected 0), "
      f"red_styles={red_count} (expected 1), fake_toc={has_fake_toc}, "
      f"real_toc={has_real_toc} (expected False), footer={has_footer} (expected False)")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create building_audit_draft.odt"
    exit 1
fi

chown ga:ga /home/ga/Documents/building_audit_draft.odt
echo "Created building_audit_draft.odt with 4 formatting violations"

# Record baseline state
echo "0" > /tmp/initial_final_file_exists
date +%s > /tmp/task_start_timestamp
sha256sum /home/ga/Documents/building_audit_draft.odt 2>/dev/null \
    | awk '{print $1}' > /tmp/initial_draft_hash || echo "" > /tmp/initial_draft_hash

# Desktop shortcut
SOFFICE_BIN="/opt/openoffice4/program/soffice"
if [ -x "$SOFFICE_BIN" ]; then
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
MimeType=application/vnd.oasis.opendocument.text;
DESKTOP
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
fi

take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Audit Report Fix Setup Complete ==="
echo "Draft file: /home/ga/Documents/building_audit_draft.odt"
echo "Expected output: /home/ga/Documents/building_audit_final.odt"
echo "Bugs planted: 10 H3 headings (should be H2), manual TOC, 3 red paragraphs, no footer"
