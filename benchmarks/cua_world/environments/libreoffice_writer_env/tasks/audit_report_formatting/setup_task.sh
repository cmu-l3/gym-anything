#!/bin/bash
# setup_task.sh — Internal Audit Report Formatting Task

source /workspace/scripts/task_utils.sh
chmod +x /workspace/tasks/audit_report_formatting/export_result.sh 2>/dev/null || true

echo "=== Setting up Audit Report Formatting Task ==="

sudo -u ga mkdir -p /home/ga/Documents

date +%s > /tmp/audit_report_task_start
chown ga:ga /tmp/audit_report_task_start 2>/dev/null || true

# Create audit_draft.docx — plain-formatted draft without proper styles,
# borders, color formatting, or proper footers. Based on real IIA audit standards.
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

section = doc.sections[0]
section.left_margin = Inches(1.0)
section.right_margin = Inches(1.0)
section.top_margin = Inches(1.0)
section.bottom_margin = Inches(1.0)

def plain(text, bold=False, size=11):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.size = Pt(size)
    run.bold = bold
    return p

def section_head(text):
    """Section heading as plain bold — no Heading style applied."""
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.size = Pt(12)
    run.bold = True
    return p

# --- Cover page area ---
p = doc.add_paragraph()
run = p.add_run("NorthBridge Financial Group")
run.font.size = Pt(16)
run.bold = True
p.alignment = WD_ALIGN_PARAGRAPH.CENTER

p = doc.add_paragraph()
run = p.add_run("INTERNAL AUDIT REPORT")
run.font.size = Pt(14)
run.bold = True
p.alignment = WD_ALIGN_PARAGRAPH.CENTER

p = doc.add_paragraph()
run = p.add_run("Q3 2024 — DRAFT")
run.font.size = Pt(12)
p.alignment = WD_ALIGN_PARAGRAPH.CENTER

plain("Audit Period: July 1, 2024 — September 30, 2024")
plain("Report Date: October 15, 2024")
plain("Prepared by: Internal Audit Department")
plain("Distribution: Audit Committee, Board of Directors, Chief Risk Officer")

doc.add_paragraph("")

# --- Executive Summary (plain — agent must put in bordered table) ---
section_head("Executive Summary")
plain(
    "This report presents the results of the Q3 2024 internal audit of NorthBridge Financial "
    "Group's operational and technology control environment, conducted in accordance with "
    "the International Standards for the Professional Practice of Internal Auditing (Standards) "
    "issued by the Institute of Internal Auditors (IIA). The audit scope encompassed information "
    "security access controls, segregation of duties in financial processing, third-party vendor "
    "management, data retention compliance, and IT change management procedures."
)
plain(
    "The audit identified five findings, two of which are rated High risk, two Medium risk, "
    "and one Low risk. The High-rated findings relate to access control deficiencies in the "
    "core banking system and segregation of duties gaps in the accounts payable process, "
    "which collectively create material risk of unauthorized transactions and financial "
    "misstatement. Management has committed to remediation plans for all findings, with "
    "High-rated items targeted for completion within 60 days. This report has been prepared "
    "in accordance with IIA Standard 2400 (Communicating Results) and the NorthBridge "
    "Internal Audit Charter approved by the Audit Committee on March 14, 2024."
)

doc.add_paragraph("")

# --- Risk Ratings Summary Table (plain — agent must add shading and colors) ---
section_head("Risk Ratings Summary")

table = doc.add_table(rows=6, cols=3)
table.style = 'Table Grid'
# Header row
hdr = table.rows[0].cells
hdr[0].text = "Finding"
hdr[1].text = "Title"
hdr[2].text = "Risk Rating"

# Data rows (no shading, no color — agent must add)
rows_data = [
    ("Finding 1", "Access Control Deficiencies", "High"),
    ("Finding 2", "Segregation of Duties Gaps", "High"),
    ("Finding 3", "Vendor Due Diligence Failures", "Medium"),
    ("Finding 4", "Data Retention Policy Violations", "Low"),
    ("Finding 5", "IT Change Management Weaknesses", "Medium"),
]
for i, (ref, title, rating) in enumerate(rows_data):
    row = table.rows[i + 1].cells
    row[0].text = ref
    row[1].text = title
    row[2].text = rating

doc.add_paragraph("")

# --- Audit Scope and Methodology ---
section_head("Audit Scope and Methodology")
plain(
    "The internal audit was conducted in accordance with IIA Standard 2200 (Engagement "
    "Planning) and Standard 2300 (Performing the Engagement). Fieldwork was performed "
    "from August 12 through September 27, 2024. Audit procedures included: (1) review "
    "of policies and procedures; (2) interviews with process owners and control operators; "
    "(3) observation of control activities; (4) transaction testing using data analytics; "
    "and (5) testing of IT general controls and application controls."
)
plain(
    "Control ratings were assigned in accordance with the NorthBridge Internal Audit "
    "Risk Rating Framework: High — significant risk of material loss or regulatory "
    "sanction requiring immediate remediation; Medium — moderate risk requiring timely "
    "remediation within 90 days; Low — limited risk requiring remediation within 180 days. "
    "All findings were discussed with management prior to issuance of this report, and "
    "management's responses are incorporated below."
)

doc.add_paragraph("")

# --- The 5 Audit Findings (plain headings — agent must apply Heading 2 style and Finding N: prefix) ---

# Finding 1
section_head("Access Control Deficiencies")
plain("Risk Rating: High | Business Owner: IT Security Department | Target Remediation: December 15, 2024")
plain(
    "Condition: Testing of 247 active user accounts in the FiServ Premier core banking "
    "system identified 38 accounts (15.4%) with excessive system privileges that exceeded "
    "job function requirements. Specifically, 12 employees in the customer service function "
    "had been granted back-end transaction override capabilities reserved for supervisors, "
    "and 9 terminated employees retained active system access for periods ranging from "
    "8 to 147 days after their separation dates. Additionally, 17 shared service accounts "
    "lacked individual attribution, preventing forensic traceability of user actions."
)
plain(
    "Criteria: IIA Standard 2120 (Risk Management); NorthBridge Information Security Policy "
    "§4.2 (Access Control); FFIEC IT Examination Handbook — Information Security Booklet "
    "(2016), pp. 47-52; NIST SP 800-53 Rev. 5, AC-2 (Account Management)."
)
plain(
    "Cause: The semi-annual user access review process was not completed for Q1 and Q2 2024 "
    "due to staff turnover in the IT Security team. HR-to-IT system provisioning/de-provisioning "
    "workflows are manual and lack automated triggers upon employee separation."
)
plain(
    "Effect: Excessive user privileges create the risk of unauthorized financial transactions "
    "and data exfiltration. Retained access for terminated employees violates regulatory "
    "requirements and could result in examination findings. Internal model estimates suggest "
    "up to $2.3M in potential exposure from unauthorized transaction risk per quarter."
)
plain(
    "Management Response: IT Security will conduct an emergency access rights review and "
    "remediate all excessive privileges within 30 days. Automated HR-IT provisioning "
    "workflows will be implemented via Workday-to-FiServ API integration by Q4 2024. "
    "Quarterly access certification reviews will resume immediately."
)

doc.add_paragraph("")

# Finding 2
section_head("Segregation of Duties Gaps")
plain("Risk Rating: High | Business Owner: Controller's Office | Target Remediation: December 31, 2024")
plain(
    "Condition: Analysis of accounts payable transaction data for the period January-September "
    "2024 identified 23 instances in which a single employee both initiated a vendor payment "
    "request and approved the corresponding disbursement in the Oracle Financial Cloud ERP "
    "system. The transactions totaled $4.7 million. Additionally, 6 employees in the treasury "
    "function had both wire initiation and wire release authority for interbank transfers, "
    "contrary to the Dual Control Policy."
)
plain(
    "Criteria: NorthBridge Financial Controls Policy §7.1 (Segregation of Duties); "
    "COSO Integrated Framework (2013), Principle 10 (Control Activities); "
    "FFIEC IT Examination Handbook — Audit Booklet (2019), pp. 18-21; "
    "Sarbanes-Oxley Act §302 (Corporate Responsibility for Financial Reports)."
)
plain(
    "Management Response: The Controller will implement system-enforced SOD controls in "
    "Oracle Financial Cloud to prevent single-person initiation and approval by December 31. "
    "Compensating controls (monthly supervisory review of all AP transactions exceeding "
    "$25,000) have been implemented immediately as interim mitigation."
)

doc.add_paragraph("")

# Finding 3
section_head("Vendor Due Diligence Failures")
plain("Risk Rating: Medium | Business Owner: Procurement | Target Remediation: January 31, 2025")
plain(
    "Condition: Review of 84 active vendor contracts with annual value exceeding $50,000 "
    "identified 19 vendors (22.6%) that had not received a risk-based due diligence review "
    "in more than 36 months. Among these, 4 vendors with access to sensitive customer data "
    "had not undergone SOC 2 Type II attestation review as required by the Third-Party Risk "
    "Management Policy. One vendor (annual contract value $1.8M) was operating under an "
    "expired contract that had not been renewed since 2021."
)
plain(
    "Management Response: Procurement will complete due diligence reviews for all 19 "
    "identified vendors by January 31, 2025, prioritizing the 4 vendors with customer data "
    "access. The vendor contract management system will be updated to generate automatic "
    "renewal alerts 180 days before contract expiration."
)

doc.add_paragraph("")

# Finding 4
section_head("Data Retention Policy Violations")
plain("Risk Rating: Low | Business Owner: Records Management | Target Remediation: March 31, 2025")
plain(
    "Condition: Sampling of the electronic document management system revealed 2,847 files "
    "exceeding their designated retention periods under the NorthBridge Records Retention "
    "Schedule. The majority (71%) were loan origination files that should have been purged "
    "in 2021. Storage of data beyond retention periods creates unnecessary litigation "
    "discovery risk and annual storage costs estimated at $47,000."
)
plain(
    "Management Response: Records Management will implement a systematic purge of "
    "overdue files by March 31, 2025, after completing a legal hold review to ensure "
    "no files are subject to active litigation holds. Automated retention enforcement "
    "will be configured in the document management system."
)

doc.add_paragraph("")

# Finding 5
section_head("IT Change Management Weaknesses")
plain("Risk Rating: Medium | Business Owner: IT Operations | Target Remediation: February 28, 2025")
plain(
    "Condition: Review of 156 IT change requests processed during Q3 2024 found that "
    "34 changes (21.8%) were deployed to the production environment without documented "
    "evidence of User Acceptance Testing (UAT). Of these, 8 changes involved modifications "
    "to core banking system calculation logic. Additionally, 12 emergency changes were "
    "implemented without post-implementation reviews, which are required by the Change "
    "Management Policy within 5 business days of emergency deployment."
)
plain(
    "Management Response: IT Operations will implement mandatory UAT sign-off as a "
    "hard gate in the ServiceNow change management workflow. A backlog review of "
    "undocumented emergency changes will be completed within 30 days."
)

doc.add_paragraph("")

# --- Conclusions ---
section_head("Conclusions and Recommendations")
plain(
    "Based on the results of this engagement, the overall rating for the Q3 2024 audit "
    "scope is Unsatisfactory with respect to information security access controls and "
    "financial process controls, and Needs Improvement for vendor management and IT "
    "change management. The two High-rated findings represent material control weaknesses "
    "requiring immediate escalation to the Board Audit Committee in accordance with "
    "IIA Standard 2060 (Reporting to Senior Management and the Board)."
)
plain(
    "The Internal Audit department will perform follow-up procedures within 90 days "
    "of the agreed remediation dates for High-rated findings, and within 180 days for "
    "Medium and Low-rated findings, in accordance with IIA Standard 2500 (Monitoring "
    "Progress)."
)

doc.add_paragraph("")

# --- Sign-Off (plain — agent must put in bordered single-cell table) ---
section_head("Report Sign-Off")
plain("Chief Audit Executive: ____________________________________")
plain("Date: ____________________________________")
plain("Audit Committee Chair: ____________________________________")

doc.save("/home/ga/Documents/audit_draft.docx")
print("Created audit_draft.docx")
PYEOF

sudo chown ga:ga /home/ga/Documents/audit_draft.docx
sudo chmod 664 /home/ga/Documents/audit_draft.docx

echo "Launching LibreOffice Writer with audit_draft.docx..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/audit_draft.docx > /tmp/writer_audit_task.log 2>&1 &"

if ! wait_for_process "soffice" 20; then
    echo "ERROR: LibreOffice failed to start"
fi

if ! wait_for_window "LibreOffice Writer" 90; then
    wait_for_window "audit_draft" 30 || true
fi

sleep 2

wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    safe_xdotool ga :1 key Escape
    sleep 0.3
    safe_xdotool ga :1 key ctrl+Home
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Take initial screenshot using ImageMagick import (scrot not in root PATH)
import -window root /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Audit Report Formatting Task Setup Complete ==="
echo "Source: /home/ga/Documents/audit_draft.docx"
echo "Required output: /home/ga/Documents/audit_final.docx"
exit 0
