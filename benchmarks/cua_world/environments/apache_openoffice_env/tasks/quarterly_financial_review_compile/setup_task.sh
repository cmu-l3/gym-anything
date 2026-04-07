#!/bin/bash
echo "=== Setting up quarterly_financial_review_compile task ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# --- Cleanup previous artifacts ---
rm -f /home/ga/Documents/PNTP_Q3_Review_FY2024.odt 2>/dev/null || true
rm -f /home/ga/Documents/Q3_review_draft.odt 2>/dev/null || true
rm -f /home/ga/Documents/financial_data.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_start_time.txt 2>/dev/null || true

# --- Create financial data JSON ---
cat > /home/ga/Documents/financial_data.json << 'DATAJSON'
{
  "company": "Pacific Northwest Timber Products, Inc.",
  "report_period": "Q3 FY2024 (July 1 - September 30, 2024)",
  "prepared_by": "Jordan Castillo, Controller",
  "revenue": {
    "lumber_wholesale": 2847000,
    "engineered_wood_products": 1203000,
    "custom_milling_services": 298500,
    "bark_and_byproducts": 87200
  },
  "operating_expenses": {
    "raw_materials_logs": 1856000,
    "direct_labor": 743200,
    "equipment_maintenance": 187400,
    "utilities_and_energy": 234800,
    "transportation_logistics": 312600,
    "insurance_and_compliance": 98500
  },
  "capital_expenditures": [
    {
      "project": "Sawmill Line #3 Modernization",
      "fy2024_actual": 1200000,
      "fy2025_budget": 2400000,
      "fy2026_projected": 800000,
      "fy2027_projected": 0,
      "fy2028_projected": 0
    },
    {
      "project": "Kiln Dryer Expansion",
      "fy2024_actual": 0,
      "fy2025_budget": 950000,
      "fy2026_projected": 950000,
      "fy2027_projected": 475000,
      "fy2028_projected": 0
    },
    {
      "project": "Wastewater Treatment Upgrade",
      "fy2024_actual": 340000,
      "fy2025_budget": 680000,
      "fy2026_projected": 0,
      "fy2027_projected": 0,
      "fy2028_projected": 0
    },
    {
      "project": "Fleet Replacement Program",
      "fy2024_actual": 425000,
      "fy2025_budget": 380000,
      "fy2026_projected": 395000,
      "fy2027_projected": 410000,
      "fy2028_projected": 430000
    }
  ],
  "capex_status_note": "Capital expenditure pacing is on track, with the Sawmill Line #3 Modernization project 60% complete. The Board should note the proposed Kiln Dryer Expansion (FY2025-FY2027) pending approval."
}
DATAJSON
chown ga:ga /home/ga/Documents/financial_data.json
chmod 644 /home/ga/Documents/financial_data.json
echo "Financial data JSON created."

# --- Generate draft ODT with intentional issues ---
python3 << 'PYEOF'
import zipfile, os, subprocess

draft_path = "/home/ga/Documents/Q3_review_draft.odt"

content_xml = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
  office:version="1.2">

  <office:automatic-styles>
    <!-- Cover page title style -->
    <style:style style:name="CoverTitle" style:family="paragraph">
      <style:paragraph-properties fo:text-align="center" fo:margin-top="0.3in" fo:margin-bottom="0.1in"/>
      <style:text-properties fo:font-size="20pt" fo:font-weight="bold"/>
    </style:style>

    <!-- Cover page subtitle style -->
    <style:style style:name="CoverSub" style:family="paragraph">
      <style:paragraph-properties fo:text-align="center" fo:margin-top="0.1in" fo:margin-bottom="0.1in"/>
      <style:text-properties fo:font-size="14pt"/>
    </style:style>

    <!-- Cover spacer -->
    <style:style style:name="CoverSpacer" style:family="paragraph">
      <style:paragraph-properties fo:text-align="center" fo:margin-top="1.5in"/>
    </style:style>

    <!-- BUG STYLE: Bold body text that looks like Heading 1 but is NOT a heading -->
    <style:style style:name="FakeBoldH1" style:family="paragraph" style:parent-style-name="Standard">
      <style:paragraph-properties fo:margin-top="0.2in" fo:margin-bottom="0.1in"/>
      <style:text-properties fo:font-size="16pt" fo:font-weight="bold"/>
    </style:style>

    <!-- Page break style -->
    <style:style style:name="PageBreakBefore" style:family="paragraph">
      <style:paragraph-properties fo:break-before="page"/>
    </style:style>

    <!-- Body text style -->
    <style:style style:name="BodyIndent" style:family="paragraph">
      <style:paragraph-properties fo:margin-top="0.08in" fo:margin-bottom="0.08in"/>
      <style:text-properties fo:font-size="12pt"/>
    </style:style>

    <!-- Table styles -->
    <style:style style:name="PLTable" style:family="table">
      <style:table-properties style:width="6.5in" table:align="margins"/>
    </style:style>
    <style:style style:name="PLTable.ColA" style:family="table-column">
      <style:table-column-properties style:column-width="3.8in"/>
    </style:style>
    <style:style style:name="PLTable.ColB" style:family="table-column">
      <style:table-column-properties style:column-width="2.7in"/>
    </style:style>
    <style:style style:name="TCHeader" style:family="table-cell">
      <style:table-cell-properties fo:padding="0.05in" fo:border="0.5pt solid #000000" fo:background-color="#2F5496"/>
    </style:style>
    <style:style style:name="TCNormal" style:family="table-cell">
      <style:table-cell-properties fo:padding="0.05in" fo:border="0.5pt solid #000000"/>
    </style:style>
    <style:style style:name="TCSection" style:family="table-cell">
      <style:table-cell-properties fo:padding="0.05in" fo:border="0.5pt solid #000000" fo:background-color="#D6DCE4"/>
    </style:style>
    <style:style style:name="TCTotal" style:family="table-cell">
      <style:table-cell-properties fo:padding="0.05in" fo:border="0.5pt solid #000000" fo:background-color="#E2EFDA"/>
    </style:style>

    <!-- Text styles for table content -->
    <style:style style:name="WhiteBold" style:family="text">
      <style:text-properties fo:color="#FFFFFF" fo:font-weight="bold"/>
    </style:style>
    <style:style style:name="BoldText" style:family="text">
      <style:text-properties fo:font-weight="bold"/>
    </style:style>
    <style:style style:name="ItalicText" style:family="text">
      <style:text-properties fo:font-style="italic"/>
    </style:style>
  </office:automatic-styles>

  <office:body>
    <office:text>

      <!-- ===== COVER PAGE ===== -->
      <text:p text:style-name="CoverSpacer"/>
      <text:p text:style-name="CoverTitle">Pacific Northwest Timber Products, Inc.</text:p>
      <text:p text:style-name="CoverSub">Quarterly Financial Review</text:p>
      <text:p text:style-name="CoverSub">Q3 FY2024 (July &#x2013; September 2024)</text:p>
      <text:p text:style-name="CoverSub"/>
      <text:p text:style-name="CoverSub">Prepared by: Jordan Castillo, Controller</text:p>
      <text:p text:style-name="CoverSub">Date: October 15, 2024</text:p>
      <text:p text:style-name="CoverSub"/>
      <text:p text:style-name="CoverSub">DRAFT &#x2014; For Board Review Only</text:p>

      <!-- ===== SECTION 1: Executive Summary (correctly styled Heading 1) ===== -->
      <text:h text:style-name="Heading_20_1" text:outline-level="1">1. Executive Summary</text:h>
      <text:p text:style-name="BodyIndent">Pacific Northwest Timber Products reported solid performance in the third quarter of fiscal year 2024. Revenue reached $4.4 million, exceeding internal projections by 3.2 percent, driven primarily by continued strong demand for engineered wood products in the Pacific Northwest commercial construction market. Lumber wholesale volumes held steady despite softening national housing starts, reflecting the strength of regional demand.</text:p>
      <text:p text:style-name="BodyIndent">Operating margins improved 1.8 percentage points year-over-year, benefiting from favorable log pricing on the spot market and a 22 percent reduction in unplanned maintenance downtime on Sawmill Lines 1 and 2 following preventive overhauls completed in Q2. Total operating expenses remained within budget, with notable savings in raw materials procurement offsetting modest increases in transportation costs due to diesel price fluctuations.</text:p>
      <text:p text:style-name="BodyIndent">Capital expenditure programs are progressing on schedule. The Sawmill Line #3 Modernization project has entered its second phase, and the proposed Kiln Dryer Expansion is presented for Board consideration in this review. Management recommends the Board approve the FY2025 capital budget as presented in Section 4.</text:p>

      <!-- ===== SECTION 2: Revenue and Expense Analysis ===== -->
      <!-- BUG: This heading uses FakeBoldH1 (bold body text) instead of Heading 1 -->
      <text:p text:style-name="PageBreakBefore"/>
      <text:p text:style-name="FakeBoldH1">2. Revenue and Expense Analysis</text:p>
      <text:p text:style-name="BodyIndent">The following table presents the consolidated profit and loss statement for Q3 FY2024. All figures are in US dollars.</text:p>

      <!-- P&L Table with WRONG totals -->
      <table:table table:name="ConsolidatedPL" table:style-name="PLTable">
        <table:table-column table:style-name="PLTable.ColA"/>
        <table:table-column table:style-name="PLTable.ColB"/>

        <!-- Row 1: Header -->
        <table:table-row>
          <table:table-cell table:style-name="TCHeader"><text:p><text:span text:style-name="WhiteBold">Category</text:span></text:p></table:table-cell>
          <table:table-cell table:style-name="TCHeader"><text:p><text:span text:style-name="WhiteBold">Q3 FY2024</text:span></text:p></table:table-cell>
        </table:table-row>

        <!-- Row 2: Revenue section label -->
        <table:table-row>
          <table:table-cell table:style-name="TCSection"><text:p><text:span text:style-name="BoldText">Revenue</text:span></text:p></table:table-cell>
          <table:table-cell table:style-name="TCSection"><text:p/></table:table-cell>
        </table:table-row>

        <!-- Row 3: Lumber Wholesale -->
        <table:table-row>
          <table:table-cell table:style-name="TCNormal"><text:p>Lumber Wholesale</text:p></table:table-cell>
          <table:table-cell table:style-name="TCNormal" office:value-type="float" office:value="2847000"><text:p>$2,847,000</text:p></table:table-cell>
        </table:table-row>

        <!-- Row 4: Engineered Wood Products -->
        <table:table-row>
          <table:table-cell table:style-name="TCNormal"><text:p>Engineered Wood Products</text:p></table:table-cell>
          <table:table-cell table:style-name="TCNormal" office:value-type="float" office:value="1203000"><text:p>$1,203,000</text:p></table:table-cell>
        </table:table-row>

        <!-- Row 5: Custom Milling Services -->
        <table:table-row>
          <table:table-cell table:style-name="TCNormal"><text:p>Custom Milling Services</text:p></table:table-cell>
          <table:table-cell table:style-name="TCNormal" office:value-type="float" office:value="298500"><text:p>$298,500</text:p></table:table-cell>
        </table:table-row>

        <!-- Row 6: Bark & Byproducts -->
        <table:table-row>
          <table:table-cell table:style-name="TCNormal"><text:p>Bark &amp; Byproducts</text:p></table:table-cell>
          <table:table-cell table:style-name="TCNormal" office:value-type="float" office:value="87200"><text:p>$87,200</text:p></table:table-cell>
        </table:table-row>

        <!-- Row 7: Total Revenue - WRONG VALUE (correct is $4,435,700) -->
        <table:table-row>
          <table:table-cell table:style-name="TCTotal"><text:p><text:span text:style-name="BoldText">Total Revenue</text:span></text:p></table:table-cell>
          <table:table-cell table:style-name="TCTotal"><text:p><text:span text:style-name="BoldText">$4,200,000</text:span></text:p></table:table-cell>
        </table:table-row>

        <!-- Row 8: Operating Expenses section label -->
        <table:table-row>
          <table:table-cell table:style-name="TCSection"><text:p><text:span text:style-name="BoldText">Operating Expenses</text:span></text:p></table:table-cell>
          <table:table-cell table:style-name="TCSection"><text:p/></table:table-cell>
        </table:table-row>

        <!-- Row 9: Raw Materials (Logs) -->
        <table:table-row>
          <table:table-cell table:style-name="TCNormal"><text:p>Raw Materials (Logs)</text:p></table:table-cell>
          <table:table-cell table:style-name="TCNormal" office:value-type="float" office:value="1856000"><text:p>$1,856,000</text:p></table:table-cell>
        </table:table-row>

        <!-- Row 10: Direct Labor -->
        <table:table-row>
          <table:table-cell table:style-name="TCNormal"><text:p>Direct Labor</text:p></table:table-cell>
          <table:table-cell table:style-name="TCNormal" office:value-type="float" office:value="743200"><text:p>$743,200</text:p></table:table-cell>
        </table:table-row>

        <!-- Row 11: Equipment Maintenance -->
        <table:table-row>
          <table:table-cell table:style-name="TCNormal"><text:p>Equipment Maintenance</text:p></table:table-cell>
          <table:table-cell table:style-name="TCNormal" office:value-type="float" office:value="187400"><text:p>$187,400</text:p></table:table-cell>
        </table:table-row>

        <!-- Row 12: Utilities & Energy -->
        <table:table-row>
          <table:table-cell table:style-name="TCNormal"><text:p>Utilities &amp; Energy</text:p></table:table-cell>
          <table:table-cell table:style-name="TCNormal" office:value-type="float" office:value="234800"><text:p>$234,800</text:p></table:table-cell>
        </table:table-row>

        <!-- Row 13: Transportation & Logistics -->
        <table:table-row>
          <table:table-cell table:style-name="TCNormal"><text:p>Transportation &amp; Logistics</text:p></table:table-cell>
          <table:table-cell table:style-name="TCNormal" office:value-type="float" office:value="312600"><text:p>$312,600</text:p></table:table-cell>
        </table:table-row>

        <!-- Row 14: Insurance & Compliance -->
        <table:table-row>
          <table:table-cell table:style-name="TCNormal"><text:p>Insurance &amp; Compliance</text:p></table:table-cell>
          <table:table-cell table:style-name="TCNormal" office:value-type="float" office:value="98500"><text:p>$98,500</text:p></table:table-cell>
        </table:table-row>

        <!-- Row 15: Total Expenses - WRONG VALUE (correct is $3,432,500) -->
        <table:table-row>
          <table:table-cell table:style-name="TCTotal"><text:p><text:span text:style-name="BoldText">Total Operating Expenses</text:span></text:p></table:table-cell>
          <table:table-cell table:style-name="TCTotal"><text:p><text:span text:style-name="BoldText">$3,500,000</text:span></text:p></table:table-cell>
        </table:table-row>

        <!-- Row 16: Net Operating Income - EMPTY (agent must add formula) -->
        <table:table-row>
          <table:table-cell table:style-name="TCTotal"><text:p><text:span text:style-name="BoldText">Net Operating Income</text:span></text:p></table:table-cell>
          <table:table-cell table:style-name="TCTotal"><text:p/></table:table-cell>
        </table:table-row>

      </table:table>

      <text:p text:style-name="BodyIndent">Revenue performance in Q3 was anchored by the engineered wood products division, which posted a 14 percent increase over the prior quarter. Custom milling services contributed steady income from specialty orders for regional timber frame builders. Bark and byproducts revenue reflects ongoing agreements with landscaping suppliers and biomass energy partners.</text:p>
      <text:p text:style-name="BodyIndent">On the expense side, raw materials remained the largest cost driver at 54 percent of total expenses. Direct labor costs were stable quarter-over-quarter, reflecting the current workforce of 87 full-time production employees. Transportation costs increased 6 percent due to a temporary diesel surcharge from the primary carrier.</text:p>

      <!-- ===== SECTION 3: Year-over-Year Comparison (correctly styled Heading 1) ===== -->
      <text:h text:style-name="Heading_20_1" text:outline-level="1">3. Year-over-Year Comparison</text:h>
      <text:p text:style-name="BodyIndent">Compared to Q3 FY2023, total revenue increased 8.5 percent from $4.09 million, while total operating expenses declined 2.1 percent from $3.51 million. The resulting improvement in net operating income represents a significant recovery from the margin compression experienced in the first half of FY2023 due to elevated log prices and supply chain disruptions in the Cascadia region.</text:p>
      <text:p text:style-name="BodyIndent">Key year-over-year drivers include a 22 percent reduction in equipment downtime following the Q2 preventive maintenance program, a 9 percent decline in spot log prices on the Pacific Northwest market, and a 14 percent increase in engineered wood product orders driven by commercial construction activity in the Portland-Seattle corridor.</text:p>

      <!-- ===== SECTION 4: Capital Expenditures ===== -->
      <!-- BUG: This heading uses FakeBoldH1 (bold body text) instead of Heading 1 -->
      <text:p text:style-name="FakeBoldH1">4. Capital Expenditures</text:p>
      <text:p text:style-name="BodyIndent">[PENDING &#x2014; Insert capital expenditure comparison table from financial_data.json. Note: this table requires landscape orientation due to multi-year column projections.]</text:p>

      <!-- ===== SECTION 5: Financial Summary and Outlook ===== -->
      <!-- BUG: This heading uses FakeBoldH1 (bold body text) instead of Heading 1 -->
      <text:p text:style-name="FakeBoldH1">5. Financial Summary and Outlook</text:p>
      <text:p text:style-name="BodyIndent">Pacific Northwest Timber Products enters Q4 FY2024 in a strong financial position. Operating margins have recovered to pre-pandemic levels, and the balance sheet supports the proposed capital investment program. Management will continue to monitor log price volatility and adjust procurement strategies as needed to protect margins through the winter harvesting season.</text:p>
      <text:p text:style-name="BodyIndent">The Board of Directors is requested to review and approve the capital expenditure projections for FY2025 through FY2028 as presented in Section 4 of this document. A formal vote on the Kiln Dryer Expansion project authorization is scheduled for the November board meeting.</text:p>

    </office:text>
  </office:body>
</office:document-content>'''

styles_xml = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
  office:version="1.2">

  <office:styles>
    <style:default-style style:family="paragraph">
      <style:paragraph-properties fo:margin-top="0in" fo:margin-bottom="0.08in"/>
      <style:text-properties fo:font-size="12pt" fo:font-family="Liberation Serif" style:font-name="Liberation Serif"/>
    </style:default-style>
    <style:style style:name="Standard" style:family="paragraph" style:class="text"/>
    <style:style style:name="Heading_20_1" style:display-name="Heading 1" style:family="paragraph" style:parent-style-name="Standard" style:next-style-name="Standard" style:class="text">
      <style:paragraph-properties fo:margin-top="0.2in" fo:margin-bottom="0.1in" fo:keep-with-next="always"/>
      <style:text-properties fo:font-size="18pt" fo:font-weight="bold" fo:color="#1F3864"/>
    </style:style>
    <style:style style:name="Heading_20_2" style:display-name="Heading 2" style:family="paragraph" style:parent-style-name="Standard" style:next-style-name="Standard" style:class="text">
      <style:paragraph-properties fo:margin-top="0.15in" fo:margin-bottom="0.08in" fo:keep-with-next="always"/>
      <style:text-properties fo:font-size="14pt" fo:font-weight="bold" fo:color="#2F5496"/>
    </style:style>
  </office:styles>

  <office:automatic-styles>
    <style:page-layout style:name="pm1">
      <style:page-layout-properties
        fo:page-width="8.5in"
        fo:page-height="11in"
        fo:margin-top="1in"
        fo:margin-bottom="1in"
        fo:margin-left="1in"
        fo:margin-right="1in"
        style:print-orientation="portrait"/>
    </style:page-layout>
  </office:automatic-styles>

  <office:master-styles>
    <style:master-page style:name="Standard" style:page-layout-name="pm1"/>
  </office:master-styles>

</office:document-styles>'''

meta_xml = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-meta
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0"
  xmlns:dc="http://purl.org/dc/elements/1.1/"
  office:version="1.2">
  <office:meta>
    <dc:title>Q3 FY2024 Quarterly Financial Review - DRAFT</dc:title>
    <dc:creator>Jordan Castillo</dc:creator>
    <meta:creation-date>2024-10-15T09:00:00</meta:creation-date>
  </office:meta>
</office:document-meta>'''

manifest_xml = '''<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">
  <manifest:file-entry manifest:media-type="application/vnd.oasis.opendocument.text" manifest:full-path="/"/>
  <manifest:file-entry manifest:media-type="text/xml" manifest:full-path="content.xml"/>
  <manifest:file-entry manifest:media-type="text/xml" manifest:full-path="styles.xml"/>
  <manifest:file-entry manifest:media-type="text/xml" manifest:full-path="meta.xml"/>
</manifest:manifest>'''

with zipfile.ZipFile(draft_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('content.xml', content_xml)
    zf.writestr('styles.xml', styles_xml)
    zf.writestr('meta.xml', meta_xml)
    zf.writestr('META-INF/manifest.xml', manifest_xml)

os.chmod(draft_path, 0o644)
subprocess.run(['chown', 'ga:ga', draft_path])
file_size = os.path.getsize(draft_path)
print(f"Draft ODT created at {draft_path}: {file_size} bytes")

# Verify the ODT is valid
try:
    with zipfile.ZipFile(draft_path, 'r') as zf:
        names = zf.namelist()
        assert 'content.xml' in names, "Missing content.xml"
        assert 'styles.xml' in names, "Missing styles.xml"
        content = zf.read('content.xml').decode('utf-8')
        assert 'FakeBoldH1' in content, "FakeBoldH1 style not found"
        assert '$4,200,000' in content, "Wrong revenue total not found"
        assert '$3,500,000' in content, "Wrong expense total not found"
        assert 'PENDING' in content, "Placeholder text not found"
        h1_count = content.count('text:outline-level="1"')
        print(f"  Heading 1 count: {h1_count} (should be 2: Sections 1 and 3)")
        print(f"  FakeBoldH1 count: {content.count('FakeBoldH1')} (should be 3: Sections 2, 4, 5)")
        print("  Draft ODT verification passed.")
except Exception as e:
    print(f"  WARNING: Draft ODT verification failed: {e}")

PYEOF

echo "Draft ODT generated."

# --- Record task start timestamp ---
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_exists

# --- Kill any existing OpenOffice instances and clean up ---
pkill -f soffice 2>/dev/null || true
sleep 2
rm -f /home/ga/.openoffice/4/user/.lock 2>/dev/null || true
# Remove recovery files to prevent Document Recovery dialog on next launch
rm -rf /home/ga/.openoffice/4/user/backup/* 2>/dev/null || true
rm -f /home/ga/Documents/.~lock.* 2>/dev/null || true
rm -f /tmp/lu*.tmp /tmp/sv*.tmp 2>/dev/null || true
# Purge RecoveryList entries from registrymodifications.xcu
python3 -c "
import re
xcu = '/home/ga/.openoffice/4/user/registrymodifications.xcu'
try:
    with open(xcu, 'r') as f:
        data = f.read()
    # Remove any RecoveryList items
    data = re.sub(r'<item oor:path=\"/org\.openoffice\.Office\.Recovery/RecoveryList\">.*?</item>', '', data, flags=re.DOTALL)
    # Remove CurrentTempURL value
    data = re.sub(r'(<prop oor:name=\"CurrentTempURL\"[^>]*><value>)file:///[^<]*(</value>)', r'\1\2', data)
    with open(xcu, 'w') as f:
        f.write(data)
    print('Recovery entries purged from registrymodifications.xcu')
except Exception as e:
    print(f'Warning: Could not clean recovery entries: {e}')
" 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer '/home/ga/Documents/Q3_review_draft.odt' &"
sleep 5

# Wait for any OpenOffice window to appear
echo "Waiting for OpenOffice window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "OpenOffice\|Q3_review\|Writer\|Welcome"; then
        echo "OpenOffice window detected."
        break
    fi
    sleep 1
done
sleep 3

# Handle the Welcome wizard if it appears (2-step wizard: Welcome -> User name)
# The wizard blocks the document from opening, so we must complete it.
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Welcome"; then
    echo "Welcome wizard detected, clicking through..."
    # Step 1: Click "Next >>" button (at ~661,470 in 1280x720 -> 992,705 in 1920x1080)
    su - ga -c "DISPLAY=:1 xdotool mousemove 992 705 click 1" 2>/dev/null || true
    sleep 2
    # Step 2: Click "Finish" button (at ~735,470 in 1280x720 -> 1103,705 in 1920x1080)
    su - ga -c "DISPLAY=:1 xdotool mousemove 1103 705 click 1" 2>/dev/null || true
    sleep 5
    echo "Wizard dismissed."
fi

# Handle Document Recovery dialog if it appears (from prior unclean shutdown)
sleep 2
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Recovery"; then
    echo "Recovery dialog detected, dismissing..."
    # Click "Cancel" button (at ~798,473 in 1280x720 -> 1197,710 in 1920x1080)
    su - ga -c "DISPLAY=:1 xdotool mousemove 1197 710 click 1" 2>/dev/null || true
    sleep 2
    # Confirm "Yes" on the are-you-sure dialog (at ~614,373 -> 921,560)
    su - ga -c "DISPLAY=:1 xdotool mousemove 921 560 click 1" 2>/dev/null || true
    sleep 3
    echo "Recovery dialog dismissed."
fi

# Wait for Writer window with the document to appear
echo "Waiting for Writer document window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Q3_review\|Writer"; then
        echo "Writer document window detected."
        break
    fi
    sleep 1
done
sleep 2

# Maximize and focus the Writer window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
# Dismiss any remaining dialogs (e.g., Tip of the Day)
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# --- Take initial screenshot ---
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "=== quarterly_financial_review_compile task setup complete ==="
