#!/bin/bash
set -e
echo "=== Setting up setup_deniable_corporate_archive task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous artifacts BEFORE recording timestamp
echo "Cleaning previous artifacts..."
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 1
rm -f /home/ga/Volumes/corporate_archive.hc
rm -f /home/ga/Keyfiles/investigation.key
rm -f /home/ga/Documents/archive_setup_report.txt
rm -rf /home/ga/Documents/decoy_files
rm -rf /home/ga/Documents/sensitive_files

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Record hashes of existing volumes to detect rename-as-solution gaming
sha256sum /home/ga/Volumes/*.hc 2>/dev/null > /tmp/pre_existing_volume_hashes.txt || true

# 2. Prepare decoy documents (realistic corporate files)
mkdir -p /home/ga/Documents/decoy_files

cat > /home/ga/Documents/decoy_files/Q3_2024_Financial_Summary.txt << 'DECOY1'
QUARTERLY FINANCIAL SUMMARY - Q3 2024
======================================
Prepared by: Corporate Finance Division
Date: October 15, 2024
Classification: Internal Use Only

Revenue Overview:
  Product Sales:      $14,230,000  (+3.2% YoY)
  Service Revenue:     $8,750,000  (+7.1% YoY)
  Licensing Fees:      $2,100,000  (-1.4% YoY)
  Total Revenue:      $25,080,000  (+4.1% YoY)

Operating Expenses:
  Cost of Goods Sold: $9,200,000
  R&D Expenditure:    $3,400,000
  Sales & Marketing:  $2,800,000
  G&A:                $1,900,000
  Total OpEx:        $17,300,000

EBITDA: $7,780,000 (31.0% margin)
Net Income: $5,120,000

Key Metrics:
  Customer Acquisition Cost: $342
  Customer Lifetime Value: $4,210
  Monthly Recurring Revenue: $3,650,000
  Churn Rate: 2.1%

Outlook: Management maintains FY2024 guidance of $98-102M revenue.
DECOY1

cat > /home/ga/Documents/decoy_files/Employee_Directory_2024.csv << 'DECOY2'
employee_id,full_name,department,title,office_location,extension,start_date
E1001,Sarah Chen,Engineering,VP of Engineering,Building A - 4th Floor,x4201,2018-03-15
E1002,Michael Torres,Engineering,Senior Software Engineer,Building A - 4th Floor,x4202,2019-07-22
E1003,Priya Patel,Engineering,DevOps Lead,Building A - 3rd Floor,x4303,2020-01-10
E1004,James Wilson,Sales,Regional Sales Director,Building B - 2nd Floor,x5201,2017-11-03
E1005,Amanda Brooks,Sales,Account Executive,Building B - 2nd Floor,x5202,2021-04-18
E1006,Robert Kim,Finance,Controller,Building C - 5th Floor,x6501,2016-09-01
E1007,Lisa Martinez,Finance,Financial Analyst,Building C - 5th Floor,x6502,2022-02-28
E1008,David Okafor,Legal,General Counsel,Building C - 6th Floor,x6601,2015-06-12
E1009,Jennifer Walsh,HR,HR Director,Building B - 1st Floor,x5101,2019-08-05
E1010,Thomas Nguyen,IT,CISO,Building A - 5th Floor,x4501,2020-11-15
DECOY2

cat > /home/ga/Documents/decoy_files/IT_Procurement_Policy_v3.txt << 'DECOY3'
IT PROCUREMENT POLICY - VERSION 3.0
====================================
Effective Date: January 1, 2024
Approved by: CTO Office
Document ID: POL-IT-2024-003

1. PURPOSE
This policy establishes guidelines for the acquisition of information
technology hardware, software, and services to ensure cost-effective
procurement aligned with organizational security standards.

2. SCOPE
Applies to all IT purchases exceeding $500, including hardware, SaaS
subscriptions, cloud infrastructure, and consulting services.

3. APPROVAL THRESHOLDS
  - Under $5,000: Department Manager approval
  - $5,000 - $25,000: IT Director + Finance approval
  - $25,000 - $100,000: VP-level + Procurement review
  - Over $100,000: C-suite approval + Board notification

4. VENDOR SECURITY REQUIREMENTS
All vendors handling company data must:
  a) Provide SOC 2 Type II certification
  b) Complete vendor security questionnaire
  c) Accept data processing agreement (DPA)
  d) Maintain cyber insurance ($5M minimum)

5. SOFTWARE STANDARDS
Approved platforms: AWS (primary cloud), Azure (DR/backup),
GitHub Enterprise (source control), Okta (identity).
Exceptions require CISO written approval.
DECOY3

# 3. Prepare sensitive investigation documents
mkdir -p /home/ga/Documents/sensitive_files

cat > /home/ga/Documents/sensitive_files/Internal_Investigation_Report_2024.txt << 'SENSITIVE1'
PRIVILEGED AND CONFIDENTIAL - ATTORNEY WORK PRODUCT
=====================================================
INTERNAL INVESTIGATION REPORT
Case Reference: INV-2024-0847
Lead Investigator: External Counsel - Morrison & Sterling LLP
Date: September 30, 2024

EXECUTIVE SUMMARY:
On June 12, 2024, the Ethics Hotline received an anonymous report
alleging that a senior manager in the Procurement Division had been
accepting undisclosed payments from vendor Nexbridge Solutions LLC
in exchange for steering contracts worth approximately $3.2 million
over a 24-month period (January 2023 - December 2024).

FINDINGS:
1. Financial analysis confirmed 17 wire transfers totaling $287,000
   from Nexbridge subsidiary accounts to accounts controlled by
   the subject's spouse (identified via KYC records from First
   Regional Bank, account ending 4471).

2. Email forensics recovered 43 communications between the subject
   and Nexbridge CEO (Mark Brennan) discussing contract terms prior
   to RFP publication. Messages were sent via personal Gmail account
   but accessed from corporate laptop (asset tag IT-2847).

3. Three competing vendors confirmed they received RFP specifications
   only 48 hours before deadline, while Nexbridge had specifications
   approximately 3 weeks in advance based on document metadata.

RECOMMENDED ACTIONS:
  - Immediate termination of subject (HR case HR-2024-1192)
  - Referral to DOJ Fraud Section per corporate compliance obligations
  - Termination of all Nexbridge contracts with 30-day wind-down
  - Enhanced procurement controls (dual-approval, blind RFP process)
SENSITIVE1

cat > /home/ga/Documents/sensitive_files/Whistleblower_Testimony_Sealed.txt << 'SENSITIVE2'
SEALED TESTIMONY - DO NOT DISTRIBUTE
======================================
Witness ID: WB-2024-003 (Identity Protected)
Deposition Date: August 14, 2024
Taken by: Morrison & Sterling LLP
Court Reporter: Certified - Transcript ID TR-84721

EXAMINATION:

Q: Please describe your role and how you became aware of the
   alleged misconduct.

A: I work in the finance department and process vendor payments.
   Starting around March 2023, I noticed that Nexbridge Solutions
   invoices were being approved unusually fast - sometimes same-day
   - while other vendors of similar size waited 30-45 days. When I
   flagged this to my supervisor, I was told to process them without
   further questions.

Q: What specifically raised your concerns?

A: Two things. First, the purchase orders for Nexbridge always came
   pre-approved by the same manager, bypassing the normal three-quote
   requirement for purchases over $10,000. Second, I discovered that
   three Nexbridge invoices totaling $412,000 referenced deliverables
   that our project managers said were never received.

Q: Did you document these observations?

A: Yes. I kept a personal log starting April 2023 with dates, invoice
   numbers, and PO references. I also saved screenshots of the
   approval workflows from our ERP system before they could be
   modified. These are stored on a personal USB drive in my home safe.

[REMAINDER OF TESTIMONY REDACTED PER PROTECTIVE ORDER]
SENSITIVE2

cat > /home/ga/Documents/sensitive_files/Evidence_Chain_of_Custody.csv << 'SENSITIVE3'
evidence_id,description,collected_by,collection_date,location_found,storage_location,hash_sha256,status
EVD-001,Corporate laptop (asset IT-2847),J. Morrison,2024-07-15,Subject office desk,Evidence Locker A-12,a3f2b8c91d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0,Sealed
EVD-002,Personal Gmail access logs (subpoena),K. Sterling,2024-07-22,Google Legal Response,Digital Evidence Server,b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4,Verified
EVD-003,First Regional Bank records (acct 4471),K. Sterling,2024-08-01,Bank compliance dept,Evidence Locker A-12,c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5,Sealed
EVD-004,Nexbridge vendor file and invoices,J. Morrison,2024-07-18,Procurement archive room,Evidence Locker B-03,d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6,Sealed
EVD-005,ERP system audit trail export,T. Nguyen (CISO),2024-07-20,SAP production server,Digital Evidence Server,e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7,Verified
EVD-006,Whistleblower USB drive (copy),K. Sterling,2024-08-16,WB-2024-003 residence,Evidence Locker A-12,f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8,Pending
EVD-007,Building access card logs (6 months),Facilities,2024-07-25,Security office,Digital Evidence Server,a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1,Verified
SENSITIVE3

cat > /home/ga/Documents/sensitive_files/Legal_Hold_Notice_Privileged.txt << 'SENSITIVE4'
ATTORNEY-CLIENT PRIVILEGED COMMUNICATION
==========================================
LEGAL HOLD NOTICE
Issued: July 10, 2024
Case Reference: INV-2024-0847 / Morrison & Sterling Matter 24-1847

TO: Thomas Nguyen, CISO
    Jennifer Walsh, HR Director
    Robert Kim, Controller

FROM: David Okafor, General Counsel

RE: Preservation of Documents Related to Nexbridge Solutions

This notice requires you to immediately preserve all documents,
communications, and electronic records related to:

1. Any interactions with Nexbridge Solutions LLC or its employees
2. Procurement decisions involving Nexbridge (PO-2023-0441 through
   PO-2024-0892)
3. All communications with or about the subject regarding
   vendor relationships or procurement approvals
4. Financial records related to payments to Nexbridge
5. ERP system logs for the Procurement module (Jan 2023 - present)

PRESERVATION OBLIGATIONS:
- Do NOT delete, modify, or relocate any responsive documents
- Disable auto-delete policies on relevant email accounts
- Preserve backup tapes covering the relevant period
- Suspend routine document destruction per retention schedule

CUSTODIANS IDENTIFIED:
  Subject - Procurement Division
  Mark Brennan - Nexbridge Solutions CEO (external)
  3 direct reports in Procurement (names in sealed addendum)

Failure to preserve may result in adverse inference sanctions
and personal liability. Contact me with questions.
SENSITIVE4

# 4. Set ownership
chown -R ga:ga /home/ga/Documents/decoy_files
chown -R ga:ga /home/ga/Documents/sensitive_files
chown -R ga:ga /home/ga/Volumes
chown -R ga:ga /home/ga/Keyfiles
chown -R ga:ga /home/ga/MountPoints

# 5. Record ground-truth checksums (hidden from agent, for verification)
mkdir -p /var/lib/veracrypt_task
chmod 700 /var/lib/veracrypt_task
sha256sum /home/ga/Documents/decoy_files/* > /var/lib/veracrypt_task/decoy_checksums.txt
sha256sum /home/ga/Documents/sensitive_files/* > /var/lib/veracrypt_task/sensitive_checksums.txt

# 6. Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

wait_for_window "VeraCrypt" 30

# Maximize and focus
WID=$(get_veracrypt_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Decoy files in: /home/ga/Documents/decoy_files/"
ls -la /home/ga/Documents/decoy_files/
echo "Sensitive files in: /home/ga/Documents/sensitive_files/"
ls -la /home/ga/Documents/sensitive_files/
