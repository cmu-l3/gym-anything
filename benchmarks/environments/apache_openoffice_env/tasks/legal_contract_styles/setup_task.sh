#!/bin/bash
# Setup script for legal_contract_styles task
# Creates a draft commercial lease agreement with formatting violations
# (all headings use direct bold formatting instead of proper Heading styles)

echo "=== Setting up Legal Contract Styles Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up any previous task artifacts
rm -f /home/ga/Documents/draft_commercial_lease.odt 2>/dev/null || true
rm -f /home/ga/Documents/commercial_lease_final.odt 2>/dev/null || true
rm -f /home/ga/Documents/firm_standards.txt 2>/dev/null || true

# Copy firm standards guide to Documents
cp /workspace/tasks/legal_contract_styles/assets/firm_standards.txt \
   /home/ga/Documents/firm_standards.txt
chown ga:ga /home/ga/Documents/firm_standards.txt

# Create the draft_commercial_lease.odt with ALL headings using
# direct formatting (bold paragraphs) instead of proper Heading styles.
# This simulates a document prepared by an outside contractor without
# following the firm's standards.

python3 << 'PYEOF'
import zipfile
import os

OUTPUT_PATH = "/home/ga/Documents/draft_commercial_lease.odt"

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

STYLES = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
  xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
  office:version="1.2">
  <office:styles>
    <style:default-style style:family="paragraph">
      <style:paragraph-properties fo:margin-top="0cm" fo:margin-bottom="0.212cm"
        fo:line-height="120%" fo:text-align="justify"/>
      <style:text-properties fo:font-size="12pt"
        style:font-name="Times New Roman" fo:color="#000000"/>
    </style:default-style>
    <style:style style:name="Default_20_Paragraph_20_Style"
      style:display-name="Default Paragraph Style"
      style:family="paragraph" style:class="text">
      <style:text-properties fo:font-size="12pt"/>
    </style:style>
    <style:style style:name="Heading_20_1" style:display-name="Heading 1"
      style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style"
      style:next-style-name="Default_20_Paragraph_20_Style"
      style:class="text">
      <style:paragraph-properties fo:margin-top="0.423cm"
        fo:margin-bottom="0.212cm" fo:keep-with-next="always"
        fo:break-before="auto"/>
      <style:text-properties fo:font-size="16pt" fo:font-weight="bold"
        fo:color="#000000"/>
    </style:style>
    <style:style style:name="Heading_20_2" style:display-name="Heading 2"
      style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style"
      style:next-style-name="Default_20_Paragraph_20_Style"
      style:class="text">
      <style:paragraph-properties fo:margin-top="0.353cm"
        fo:margin-bottom="0.176cm" fo:keep-with-next="always"/>
      <style:text-properties fo:font-size="13pt" fo:font-weight="bold"
        fo:color="#000000"/>
    </style:style>
    <style:style style:name="Title" style:display-name="Title"
      style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style"
      style:class="chapter">
      <style:paragraph-properties fo:text-align="center"
        fo:margin-bottom="0.5cm"/>
      <style:text-properties fo:font-size="18pt" fo:font-weight="bold"/>
    </style:style>
    <style:style style:name="Subtitle" style:display-name="Subtitle"
      style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style">
      <style:paragraph-properties fo:text-align="center"
        fo:margin-bottom="0.3cm"/>
      <style:text-properties fo:font-size="13pt" fo:font-style="italic"/>
    </style:style>
    <style:style style:name="Text_20_Body" style:display-name="Text Body"
      style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style">
      <style:paragraph-properties fo:margin-top="0cm"
        fo:margin-bottom="0.212cm"/>
    </style:style>
  </office:styles>
  <office:automatic-styles>
    <style:page-layout style:name="pm1">
      <style:page-layout-properties fo:page-width="21.59cm"
        fo:page-height="27.94cm" style:print-orientation="portrait"
        fo:margin-top="2.54cm" fo:margin-bottom="2.54cm"
        fo:margin-left="3.18cm" fo:margin-right="3.18cm"/>
    </style:page-layout>
  </office:automatic-styles>
  <office:master-styles>
    <style:master-page style:name="Standard"
      style:page-layout-name="pm1">
    </style:master-page>
  </office:master-styles>
</office:document-styles>"""

META = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-meta
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0"
  office:version="1.2">
  <office:meta>
    <meta:creation-date>2026-01-15T09:00:00</meta:creation-date>
    <meta:initial-creator>Outside Contractor</meta:initial-creator>
  </office:meta>
</office:document-meta>"""

# Build the content XML with FAKE headings (bold paragraphs, NOT proper Heading styles)
# Each section/subsection heading is a bold paragraph, not a text:h element.
# The agent must convert these to proper Heading 1 / Heading 2 styles.

def fake_h1(text):
    """Fake heading 1: bold paragraph with large font — NOT a proper heading style."""
    return f'''      <text:p text:style-name="FakeH1">{text}</text:p>'''

def fake_h2(text):
    """Fake heading 2: bold paragraph with medium font — NOT a proper heading style."""
    return f'''      <text:p text:style-name="FakeH2">{text}</text:p>'''

def body(text):
    """Regular body paragraph."""
    return f'''      <text:p text:style-name="BodyText">{text}</text:p>'''

def blank():
    return '''      <text:p text:style-name="BodyText"/>'''

sections = [
    f'''      <text:p text:style-name="Title">COMMERCIAL LEASE AGREEMENT</text:p>''',
    f'''      <text:p text:style-name="Subtitle">Pacific Properties LLC (Landlord) and Meridian Analytics Inc. (Tenant)</text:p>''',
    blank(),
    body("This Commercial Lease Agreement (\"Agreement\") is entered into as of January 15, 2026, between the parties identified herein. This Agreement governs the lease of certain commercial premises located in Santa Clara County, California, and sets forth the rights and obligations of both Landlord and Tenant with respect thereto."),
    blank(),

    fake_h1("1. PARTIES"),
    fake_h2("1.1 Landlord"),
    body("Pacific Properties LLC, a California limited liability company (\"Landlord\"), having its principal place of business at 4200 Market Street, San Francisco, California 94102. Landlord&#x2019;s authorized representative for purposes of this Agreement is its Managing Member, Robert J. Callahan."),
    fake_h2("1.2 Tenant"),
    body("Meridian Analytics Inc., a Delaware corporation authorized to do business in the State of California (\"Tenant\"), with its principal executive offices located at 101 Innovation Circle, Menlo Park, California 94025. Tenant&#x2019;s authorized representative is its Chief Operating Officer, Diana Park."),
    fake_h2("1.3 Property Manager"),
    body("Bay Area Commercial Management Group, LLC (\"Property Manager\"), acting as agent for Landlord pursuant to a separate property management agreement. All communications from Tenant regarding day-to-day building operations shall be directed to the Property Manager at the address set forth in Section 10.3."),
    blank(),

    fake_h1("2. PREMISES"),
    fake_h2("2.1 Description of Leased Premises"),
    body("Landlord hereby leases to Tenant the commercial office space designated as Suite 200, located on the second floor of the building known as Palo Alto Technology Center, situated at 4500 Technology Drive, Palo Alto, California 94304 (the \"Building\"), including all interior improvements and fixtures existing therein as of the Commencement Date (collectively, the \"Premises\")."),
    fake_h2("2.2 Measurement and Square Footage"),
    body("The Premises contain approximately 8,450 rentable square feet. The parties acknowledge that the square footage figure is an approximation and that any deviation of five percent (5%) or less from this figure shall not give rise to any adjustment of rent or claim by either party. Tenant has had an opportunity to inspect and measure the Premises prior to execution of this Agreement."),
    fake_h2("2.3 Common Areas and Facilities"),
    body("Tenant shall have the non-exclusive right, in common with other tenants and occupants of the Building, to use the common areas of the Building and the land upon which the Building is situated, including lobbies, elevators, parking facilities, restrooms, and other facilities as designated by Landlord from time to time. Landlord reserves the right to modify common areas provided such modifications do not materially and adversely affect Tenant&#x2019;s access to or use of the Premises."),
    blank(),

    fake_h1("3. LEASE TERM"),
    fake_h2("3.1 Commencement Date"),
    body("The term of this Lease shall commence on March 1, 2026 (the \"Commencement Date\"), provided that all conditions precedent set forth in Section 3.1(a) have been satisfied. If the Premises are not ready for occupancy by the Commencement Date due to reasons not attributable to Tenant, Tenant&#x2019;s obligation to pay Base Rent shall be abated until the Premises are tendered."),
    fake_h2("3.2 Lease Expiration Date"),
    body("Unless sooner terminated or extended in accordance with the provisions of this Agreement, the Lease term shall expire at 11:59 p.m. on February 28, 2031 (the \"Expiration Date\"), representing a term of exactly five (5) years from the Commencement Date. Time is of the essence with respect to all dates in this Agreement."),
    fake_h2("3.3 Holdover Provisions"),
    body("If Tenant remains in possession of the Premises after the Expiration Date without the execution of a new lease or written renewal agreement, such holdover shall be deemed a month-to-month tenancy at a monthly rental equal to one hundred fifty percent (150%) of the last monthly installment of Base Rent payable under this Agreement. All other terms and conditions of this Agreement shall remain in full force and effect during any holdover period."),
    blank(),

    fake_h1("4. BASE RENT AND ADDITIONAL CHARGES"),
    fake_h2("4.1 Monthly Base Rent Schedule"),
    body("Tenant shall pay Landlord as Base Rent for the Premises the following monthly amounts, payable in advance on the first day of each calendar month during the term: (a) Lease Months 1-12: $24,505.00 per month ($2.90 per rentable square foot per month); (b) Lease Months 13-24: $25,230.50 per month ($2.987 per rentable sq. ft. per month); (c) Lease Months 25-36: $25,987.42 per month ($3.077 per rentable sq. ft. per month); (d) Lease Months 37-48: $26,767.04 per month ($3.169 per rentable sq. ft. per month); (e) Lease Months 49-60: $27,570.05 per month ($3.264 per rentable sq. ft. per month). Base Rent for any partial month shall be prorated on a per diem basis."),
    fake_h2("4.2 Annual Rent Adjustments"),
    body("In addition to the foregoing scheduled increases, each annual rent adjustment reflects a three percent (3%) annual escalation applied to the Base Rent of the immediately preceding lease year. Landlord and Tenant have agreed in advance to the rent schedule set forth above for the full five-year term, and no further escalation adjustments shall be made except as expressly provided herein."),
    fake_h2("4.3 Late Payment Penalties"),
    body("If Tenant fails to pay Base Rent or any other monetary amount due under this Agreement within five (5) business days of its due date, Tenant shall pay Landlord a late charge equal to five percent (5%) of the overdue amount. This late charge is intended to compensate Landlord for additional administrative costs incurred and does not constitute a waiver of Landlord&#x2019;s other remedies. Interest at the rate of twelve percent (12%) per annum shall also accrue on all overdue amounts."),
    blank(),

    fake_h1("5. SECURITY DEPOSIT"),
    fake_h2("5.1 Amount and Timing of Payment"),
    body("Concurrently with Tenant&#x2019;s execution of this Agreement, Tenant shall deposit with Landlord the sum of Forty-Nine Thousand Ten Dollars ($49,010.00) as a security deposit (the \"Security Deposit\"), representing two months&#x2019; Base Rent at the initial rate. The Security Deposit shall be held by Landlord as security for the faithful performance by Tenant of all terms, covenants, and conditions of this Agreement."),
    fake_h2("5.2 Conditions for Return"),
    body("The Security Deposit, or any balance thereof, shall be returned to Tenant within twenty-one (21) days following the later of: (a) the termination of this Agreement; or (b) Tenant&#x2019;s surrender of the Premises to Landlord in the condition required by this Agreement. Landlord may apply the Security Deposit to remedy any default by Tenant or to repair damages to the Premises caused by Tenant, beyond ordinary wear and tear. Landlord shall provide an itemized written statement of any deductions."),
    blank(),

    fake_h1("6. PERMITTED USE AND OCCUPANCY"),
    fake_h2("6.1 Permitted Business Use"),
    body("Tenant shall use and occupy the Premises solely for general office purposes and activities incidental thereto, including software development, data analytics services, and related technology business operations consistent with Tenant&#x2019;s stated line of business. No use shall be made that would (a) void or cause an increase in the premium of any insurance policy covering the Building; (b) create a public or private nuisance; or (c) violate any applicable laws, ordinances, or governmental regulations."),
    fake_h2("6.2 Prohibited Activities"),
    body("Tenant shall not use the Premises for any of the following: retail sales open to the general public; medical, dental, or healthcare services; manufacturing, assembly, or storage of hazardous materials; restaurant or food preparation; residential use; or any use that would increase the occupancy load above applicable building code limits. Tenant shall not permit any lien, encumbrance, or claim to be filed against the Premises arising from Tenant&#x2019;s activities."),
    fake_h2("6.3 Compliance with Laws and Regulations"),
    body("Tenant shall, at its sole cost and expense, comply with all applicable laws, ordinances, rules, regulations, and orders of any governmental authority having jurisdiction over the Premises and Tenant&#x2019;s use thereof, including without limitation the Americans with Disabilities Act (ADA), Environmental Protection Agency regulations, OSHA requirements, and all local fire and safety codes, insofar as such compliance relates to Tenant&#x2019;s specific use of the Premises or Tenant&#x2019;s alterations thereto."),
    blank(),

    fake_h1("7. MAINTENANCE AND REPAIRS"),
    fake_h2("7.1 Landlord&#x2019;s Maintenance Obligations"),
    body("Landlord shall maintain in good condition and repair the structural components of the Building, including the roof, exterior walls, foundation, and load-bearing elements; the Building&#x2019;s mechanical, electrical, plumbing, and HVAC systems serving the Building as a whole; the lobbies, corridors, elevators, stairwells, and other common areas; and the exterior grounds, parking lots, and landscaping. Landlord shall respond to maintenance requests within a commercially reasonable time."),
    fake_h2("7.2 Tenant&#x2019;s Maintenance Obligations"),
    body("Tenant shall, at its own expense, maintain and keep in good order and repair the interior of the Premises, including all non-structural interior improvements, fixtures, equipment, and personal property. Tenant shall immediately report to Landlord any condition in the Premises that may require repair or that could result in damage to the Building or to other tenants. Tenant shall not permit waste or damage to the Premises. At the expiration of the Lease term, Tenant shall surrender the Premises in substantially the same condition as received, reasonable wear and tear excepted."),
    blank(),

    fake_h1("8. ALTERATIONS AND IMPROVEMENTS"),
    fake_h2("8.1 Prior Written Approval Required"),
    body("Tenant shall not make any alterations, additions, or improvements to the Premises (collectively, \"Alterations\") without the prior written consent of Landlord, which consent shall not be unreasonably withheld, conditioned, or delayed for non-structural, cosmetic Alterations costing less than Twenty-Five Thousand Dollars ($25,000.00). Tenant&#x2019;s request for consent shall include detailed plans and specifications, names of proposed contractors, and evidence of insurance. All approved Alterations shall be performed in a workmanlike manner and in compliance with all applicable codes."),
    fake_h2("8.2 Restoration of Premises"),
    body("Upon the expiration or earlier termination of this Agreement, Tenant shall, at Landlord&#x2019;s election, either: (a) remove all Alterations made by Tenant and restore the Premises to their original condition, reasonable wear and tear excepted; or (b) surrender the Premises including all Alterations, which shall become the property of Landlord at no cost. Landlord shall notify Tenant at the time it approves any Alterations whether restoration will be required upon Lease expiration. Tenant&#x2019;s obligation to restore shall survive termination of this Agreement."),
    blank(),

    fake_h1("9. INSURANCE AND INDEMNIFICATION"),
    fake_h2("9.1 Tenant&#x2019;s Insurance Requirements"),
    body("Throughout the term of this Lease, Tenant shall obtain and maintain, at its sole cost, the following insurance coverages from insurers licensed in California with an AM Best financial strength rating of A-VII or better: (a) Commercial General Liability insurance with limits of not less than Two Million Dollars ($2,000,000) per occurrence and Five Million Dollars ($5,000,000) in the aggregate; (b) Property insurance covering Tenant&#x2019;s personal property and trade fixtures on a replacement cost basis; (c) Workers&#x2019; Compensation insurance as required by California law; and (d) Business Interruption insurance. Tenant shall name Landlord and Property Manager as additional insureds and shall provide certificates of insurance prior to occupancy."),
    fake_h2("9.2 Landlord&#x2019;s Insurance"),
    body("Landlord shall obtain and maintain property insurance on the Building on an all-risk or special-form basis for full replacement cost value, and commercial general liability insurance with limits customary for similar commercial properties. Landlord&#x2019;s insurance shall not cover Tenant&#x2019;s personal property, trade fixtures, or improvements installed by Tenant. Tenant acknowledges that Landlord&#x2019;s insurance provides no benefit to Tenant and that Tenant must independently secure adequate coverage."),
    fake_h2("9.3 Mutual Indemnification"),
    body("Each party (the \"Indemnifying Party\") agrees to indemnify, defend, and hold harmless the other party and its officers, directors, employees, agents, and successors (collectively, the \"Indemnified Parties\") from and against any and all claims, damages, losses, costs, and expenses (including reasonable attorneys&#x2019; fees) arising out of or related to: (a) the Indemnifying Party&#x2019;s negligence or willful misconduct; (b) any breach of this Agreement by the Indemnifying Party; or (c) any third-party claim arising from the Indemnifying Party&#x2019;s activities in or about the Premises. This indemnification obligation shall survive the expiration or termination of this Agreement."),
    blank(),

    fake_h1("10. DEFAULT, REMEDIES, AND DISPUTE RESOLUTION"),
    fake_h2("10.1 Events of Tenant Default"),
    body("Each of the following shall constitute an \"Event of Default\" by Tenant: (a) failure to pay Base Rent or any other monetary obligation within five (5) business days after written notice from Landlord; (b) failure to cure any non-monetary default within thirty (30) days after written notice (or such additional time as is reasonably necessary if the default cannot reasonably be cured within thirty (30) days, provided Tenant commences cure within such period); (c) Tenant&#x2019;s abandonment of the Premises; (d) Tenant&#x2019;s filing for bankruptcy or assignment for the benefit of creditors; or (e) any material misrepresentation by Tenant in connection with this Agreement."),
    fake_h2("10.2 Landlord&#x2019;s Remedies Upon Default"),
    body("Upon the occurrence of an uncured Event of Default, Landlord shall have the following remedies, which are cumulative and not exclusive: (a) terminate this Lease by written notice and recover from Tenant all damages allowed under California Civil Code Section 1951.2, including the difference between unpaid rent and the rental value of the Premises for the remainder of the term; (b) continue this Lease in effect under California Civil Code Section 1951.4 and collect rent as it becomes due; (c) pursue any other remedy available at law or in equity; or (d) re-enter the Premises using lawful means and re-let the Premises on Tenant&#x2019;s account. Landlord shall have a duty to mitigate its damages."),
    fake_h2("10.3 Attorney&#x2019;s Fees and Costs"),
    body("In any action or proceeding arising out of or relating to this Agreement, including enforcement of any provision hereof or resolution of any dispute between the parties, the prevailing party shall be entitled to recover its reasonable attorney&#x2019;s fees, court costs, and litigation expenses from the non-prevailing party. This provision shall apply to any arbitration proceeding as well as to judicial proceedings, appeals, and proceedings to enforce an arbitration award."),
    blank(),
    body("IN WITNESS WHEREOF, the parties have executed this Commercial Lease Agreement as of the date first written above."),
    blank(),
    body("LANDLORD: Pacific Properties LLC"),
    blank(),
    body("By: ___________________________"),
    body("Name: Robert J. Callahan"),
    body("Title: Managing Member"),
    body("Date: _______________"),
    blank(),
    body("TENANT: Meridian Analytics Inc."),
    blank(),
    body("By: ___________________________"),
    body("Name: Diana Park"),
    body("Title: Chief Operating Officer"),
    body("Date: _______________"),
]

CONTENT = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
  xmlns:dc="http://purl.org/dc/elements/1.1/"
  office:version="1.2">
  <office:automatic-styles>
    <!-- FakeH1: bold large paragraph — simulates what an outside contractor
         would produce when manually formatting headings without proper styles -->
    <style:style style:name="FakeH1" style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style">
      <style:paragraph-properties fo:margin-top="0.4cm"
        fo:margin-bottom="0.2cm" fo:keep-with-next="always"/>
      <style:text-properties fo:font-weight="bold" fo:font-size="16pt"
        fo:color="#000000"/>
    </style:style>
    <!-- FakeH2: bold medium paragraph — same problem at subsection level -->
    <style:style style:name="FakeH2" style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style">
      <style:paragraph-properties fo:margin-top="0.3cm"
        fo:margin-bottom="0.15cm" fo:keep-with-next="always"/>
      <style:text-properties fo:font-weight="bold" fo:font-size="13pt"
        fo:color="#000000"/>
    </style:style>
    <style:style style:name="BodyText" style:family="paragraph"
      style:parent-style-name="Default_20_Paragraph_20_Style">
      <style:paragraph-properties fo:margin-top="0cm"
        fo:margin-bottom="0.2cm" fo:text-align="justify"/>
      <style:text-properties fo:font-size="12pt"/>
    </style:style>
  </office:automatic-styles>
  <office:body>
    <office:text>
""" + "\n".join(sections) + """
    </office:text>
  </office:body>
</office:document-content>"""

os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

with zipfile.ZipFile(OUTPUT_PATH, 'w', zipfile.ZIP_DEFLATED) as zf:
    # mimetype must be first and uncompressed
    zf.writestr(zipfile.ZipInfo('mimetype'), MIMETYPE)
    zf.writestr('META-INF/manifest.xml', MANIFEST)
    zf.writestr('content.xml', CONTENT)
    zf.writestr('styles.xml', STYLES)
    zf.writestr('meta.xml', META)

print(f"Created {OUTPUT_PATH} ({os.path.getsize(OUTPUT_PATH)} bytes)")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create draft_commercial_lease.odt"
    exit 1
fi

chown ga:ga /home/ga/Documents/draft_commercial_lease.odt
echo "Created draft_commercial_lease.odt with fake heading styles (formatting violations)"

# Record baseline state
echo "0" > /tmp/initial_final_file_exists
date +%s > /tmp/task_start_timestamp
ls -la /home/ga/Documents/ > /tmp/initial_dir_state 2>&1 || true

# Record SHA hash of draft file so we can verify the final file is DIFFERENT
sha256sum /home/ga/Documents/draft_commercial_lease.odt 2>/dev/null \
    | awk '{print $1}' > /tmp/initial_draft_hash || echo "" > /tmp/initial_draft_hash

# Ensure desktop shortcut exists
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
    echo "Desktop shortcut created"
fi

take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Legal Contract Styles Setup Complete ==="
echo "Draft file: /home/ga/Documents/draft_commercial_lease.odt"
echo "Standards guide: /home/ga/Documents/firm_standards.txt"
echo "Expected output: /home/ga/Documents/commercial_lease_final.odt"
