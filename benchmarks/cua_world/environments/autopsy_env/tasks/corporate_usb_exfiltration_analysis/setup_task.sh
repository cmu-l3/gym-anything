#!/bin/bash
# Setup script for corporate_usb_exfiltration_analysis task
# Creates two NTFS disk images (corporate repo + suspect USB) with:
#   - Exact file copies (exfiltrated)
#   - Modified copies (same name, different content)
#   - Deleted files on USB
#   - NTFS Alternate Data Streams on USB
# Also generates a corporate hash inventory file and ground truth JSON.

echo "=== Setting up corporate_usb_exfiltration_analysis task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/exfiltration_result.json /tmp/exfiltration_gt.json \
      /tmp/exfiltration_start_time 2>/dev/null || true

rm -f /home/ga/evidence/corporate_repo.dd \
      /home/ga/evidence/suspect_usb.dd \
      /home/ga/evidence/corporate_hashes.txt 2>/dev/null || true

for d in /home/ga/Cases/IP_Theft_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

rm -rf /home/ga/Reports
mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports 2>/dev/null || true
mkdir -p /home/ga/evidence

# ── Create Corporate Repository Image (16MB NTFS) ────────────────────────────
CORP_IMG="/home/ga/evidence/corporate_repo.dd"
CORP_MNT="/tmp/mnt_corp_repo"

echo "Creating corporate repository NTFS image..."
dd if=/dev/zero of="$CORP_IMG" bs=1M count=16 2>/dev/null
mkfs.ntfs -F -q -L "CORP_SHARE" "$CORP_IMG"

mkdir -p "$CORP_MNT"
if ! mount -t ntfs-3g -o loop "$CORP_IMG" "$CORP_MNT"; then
    echo "ERROR: Failed to mount corporate image"
    exit 1
fi

# Create department directories
mkdir -p "$CORP_MNT/Engineering"
mkdir -p "$CORP_MNT/Finance"
mkdir -p "$CORP_MNT/Legal"
mkdir -p "$CORP_MNT/Research"
mkdir -p "$CORP_MNT/Executive"

# ── Engineering files (6 files) ──
cat > "$CORP_MNT/Engineering/circuit_design_v3.txt" << 'FILEEOF'
ACME Corp - Proprietary Circuit Board Design v3.2
Classification: CONFIDENTIAL
Date: 2024-03-15
Lead Engineer: Dr. Sarah Chen

Component Layout Specification:
  MCU: STM32F407VGT6 @ 168MHz
  ADC: ADS1256 24-bit delta-sigma, 8-channel
  Power: LM3150 buck converter, 3.3V/5V rail
  Comm: CC2652R1 Zigbee 3.0 / Thread module

PCB Stack-up: 6-layer, 1.6mm FR4
  L1: Signal (impedance-controlled 50 ohm)
  L2: Ground plane
  L3: Power (3.3V)
  L4: Signal (high-speed differential pairs)
  L5: Ground plane
  L6: Signal + power routing

Critical trace lengths must not exceed 25mm for high-speed ADC clock.
Decoupling: 100nF MLCC within 3mm of each VDD pin.
FILEEOF

cat > "$CORP_MNT/Engineering/firmware_specs.txt" << 'FILEEOF'
Firmware Release Notes - v2.8.1 (Internal Only)
Build: 20240410-1847-release
Target: STM32F407VGT6

Changes in this release:
  - Fixed race condition in SPI DMA transfer (JIRA-4521)
  - Optimized FFT computation: 40% faster on 1024-point window
  - Added watchdog timer recovery for sensor bus lockup
  - Updated BLE stack to v5.3 with LE Audio support

Known issues:
  - ADC channel 7 shows 2-LSB offset drift above 60C (JIRA-4533)
  - OTA update fails if flash sector 11 is write-protected

Memory footprint: 287KB flash / 94KB RAM (78% / 47% utilization)
Boot time: 340ms to application main loop
FILEEOF

cat > "$CORP_MNT/Engineering/test_protocol_q2.txt" << 'FILEEOF'
Quality Assurance Test Protocol - Q2 2024
Document: QA-TP-2024-Q2-007
Approved by: Quality Director M. Rodriguez

Environmental Testing Matrix:
  Temperature: -20C to +85C (MIL-STD-810H Method 501.7)
  Humidity: 95% RH non-condensing @ 40C, 72h exposure
  Vibration: 5-500Hz, 2.5g RMS, 3-axis, 8h per axis
  Shock: 40g half-sine, 11ms pulse, 3 axes x 2 directions

Pass Criteria:
  - All functional tests pass post-exposure
  - Current draw within 5% of baseline
  - No visible PCB damage under 10x magnification
  - BER < 1e-6 on communication link
FILEEOF

cat > "$CORP_MNT/Engineering/sensor_calibration.csv" << 'FILEEOF'
sensor_id,channel,offset_mv,gain_factor,temp_coeff_ppm,cal_date,cal_technician
SN-2024-0001,CH0,-0.342,1.00023,4.7,2024-02-12,T.Williams
SN-2024-0001,CH1,0.118,0.99987,5.1,2024-02-12,T.Williams
SN-2024-0001,CH2,-0.015,1.00012,4.3,2024-02-12,T.Williams
SN-2024-0002,CH0,0.521,0.99945,6.2,2024-02-13,T.Williams
SN-2024-0002,CH1,-0.087,1.00031,5.8,2024-02-13,T.Williams
SN-2024-0002,CH2,0.203,0.99998,4.9,2024-02-13,T.Williams
SN-2024-0003,CH0,-0.444,1.00056,7.1,2024-02-14,K.Park
SN-2024-0003,CH1,0.067,0.99972,6.6,2024-02-14,K.Park
SN-2024-0003,CH2,-0.291,1.00008,5.4,2024-02-14,K.Park
FILEEOF

cat > "$CORP_MNT/Engineering/build_manifest.txt" << 'FILEEOF'
Production Build Manifest - Lot 2024-Q1-Batch-C
Date: 2024-01-22
Manufacturing Site: Shenzhen Facility B3

Bill of Materials (BOM) Summary:
  Total unique parts: 147
  Total placements: 623
  PCB panels per batch: 50 (4-up panelization)
  Yield target: >= 98.5%

Critical components (long lead-time):
  STM32F407VGT6: 200 units ordered (Mouser PO-87432)
  ADS1256IDBR: 200 units ordered (DigiKey PO-91023)
  CC2652R1F: 250 units ordered (TI direct, 12-week lead)
FILEEOF

cat > "$CORP_MNT/Engineering/hardware_bom.csv" << 'FILEEOF'
part_number,description,manufacturer,quantity,unit_cost_usd,supplier,lead_time_weeks
STM32F407VGT6,MCU ARM Cortex-M4 168MHz,STMicroelectronics,200,8.45,Mouser,4
ADS1256IDBR,ADC 24-bit 30kSPS 8-ch,Texas Instruments,200,12.30,DigiKey,8
CC2652R1F,Wireless MCU Zigbee/Thread,Texas Instruments,250,4.85,TI Direct,12
LM3150MH,Buck Converter 42V 1.5A,Texas Instruments,400,2.15,Mouser,3
TPS62160DSGR,Buck Converter 3.3V 1A,Texas Instruments,400,1.92,DigiKey,2
SN65HVD230DR,CAN Transceiver 3.3V,Texas Instruments,200,1.45,Mouser,2
FILEEOF

# ── Finance files (6 files) ──
cat > "$CORP_MNT/Finance/revenue_forecast_2024.txt" << 'FILEEOF'
ACME Corp Revenue Forecast - FY2024
Classification: CONFIDENTIAL - Finance Only
Prepared by: CFO Office, January 2024

Quarterly Revenue Projections (USD millions):
  Q1: $42.3M (Actual: sensors + legacy products)
  Q2: $48.7M (New IoT platform launch expected)
  Q3: $51.2M (Channel ramp + government contracts)
  Q4: $56.8M (Holiday season + automotive tier-1 orders)

Total FY2024 projected: $199.0M (+18% YoY)
Gross margin target: 62%
EBITDA target: $47.8M (24% margin)
FILEEOF

cat > "$CORP_MNT/Finance/vendor_payments_q3.csv" << 'FILEEOF'
vendor_id,vendor_name,invoice_number,amount_usd,payment_date,status,category
V-001,Shenzhen PCB Manufacturing Co.,INV-2024-3341,187450.00,2024-07-15,PAID,Manufacturing
V-002,Mouser Electronics,INV-2024-8872,34521.75,2024-07-22,PAID,Components
V-003,DigiKey Corporation,INV-2024-1123,28944.50,2024-08-01,PAID,Components
V-004,AWS Cloud Services,INV-2024-0089,12340.00,2024-08-15,PAID,Infrastructure
V-005,Keil MDK License Renewal,INV-2024-7756,8500.00,2024-09-01,PENDING,Software
V-006,Bureau Veritas Testing,INV-2024-4412,22100.00,2024-09-10,PAID,Certification
FILEEOF

cat > "$CORP_MNT/Finance/audit_trail.log" << 'FILEEOF'
2024-01-15T09:12:33Z INFO  User=CFO Action=APPROVE Document=Q4_bonus_pool Amount=$2.4M
2024-01-28T14:05:21Z INFO  User=Controller Action=POST JournalEntry=JE-2024-0042 Amount=$187,450
2024-02-10T11:30:45Z WARN  User=AP_Clerk Action=OVERRIDE Invoice=INV-2024-3341 Reason=duplicate_check_bypass
2024-03-01T16:44:12Z INFO  User=CFO Action=APPROVE Document=Q1_forecast_revision
2024-03-15T08:22:09Z INFO  User=Controller Action=CLOSE Period=FY2024-Q1
2024-04-02T10:15:33Z ALERT User=IT_Admin Action=ACCESS_REVOKE Target=j.hayes Reason=termination_pending
FILEEOF

cat > "$CORP_MNT/Finance/budget_allocation.txt" << 'FILEEOF'
FY2024 Departmental Budget Allocation
Approved: Board Resolution BR-2024-003

Department Budgets:
  Engineering:    $32.5M  (R&D + manufacturing ops)
  Sales/Marketing: $18.2M  (channels + digital + events)
  Finance/Legal:  $6.8M   (compliance + audit + counsel)
  Research:       $14.1M  (advanced materials + algorithms)
  Executive/Admin: $4.2M  (C-suite + facilities + HR)
  IT/Security:    $8.7M   (infrastructure + SOC + tooling)

Total OpEx: $84.5M
CapEx Reserve: $12.0M (facility expansion Phase 2)
FILEEOF

cat > "$CORP_MNT/Finance/expense_report_q2.csv" << 'FILEEOF'
employee_id,name,department,expense_date,category,amount_usd,description,approved_by
E-1042,Sarah Chen,Engineering,2024-04-12,Travel,2340.00,Embedded World Nuremberg,M.Rodriguez
E-1042,Sarah Chen,Engineering,2024-05-08,Equipment,890.00,Oscilloscope probe set,M.Rodriguez
E-1087,Jordan Hayes,Research,2024-04-22,Conference,1850.00,IEEE Sensors Conf Vienna,R.Patel
E-1087,Jordan Hayes,Research,2024-06-15,Software,450.00,MATLAB license renewal,R.Patel
E-1103,Lisa Wang,Finance,2024-05-20,Training,1200.00,ACFE certification course,D.Morrison
FILEEOF

cat > "$CORP_MNT/Finance/tax_filing_notes.txt" << 'FILEEOF'
FY2023 Tax Filing Notes (Internal)
Prepared: March 2024

R&D Tax Credit (Section 41):
  Qualified Research Expenses: $28.4M
  Credit claimed: $2.84M (10% simplified method)
  Supporting documentation: Lab notebooks, timesheets, project codes

Foreign-Derived Intangible Income (FDII):
  Export revenue qualifying: $34.2M
  FDII deduction: $2.7M
  Transfer pricing study completed by PwC (Report #TP-2024-ACME-001)
FILEEOF

# ── Legal files (6 files) ──
cat > "$CORP_MNT/Legal/patent_draft_2024_001.txt" << 'FILEEOF'
PATENT APPLICATION DRAFT
Title: Multi-Modal Sensor Fusion System with Adaptive Calibration
Application No: [PENDING]
Filing Date: [TARGET: 2024-06-30]
Inventors: Dr. Sarah Chen, Dr. Raj Patel, Jordan Hayes

ABSTRACT:
A system and method for real-time fusion of heterogeneous sensor data
streams using adaptive Kalman filtering with online parameter estimation.
The invention provides sub-millisecond latency fusion of accelerometer,
gyroscope, magnetometer, and barometric altitude data with automatic
detection and compensation of sensor degradation.

CLAIMS:
1. A method for adaptive sensor calibration comprising:
   a) continuously monitoring sensor drift parameters
   b) applying recursive least-squares estimation
   c) updating calibration coefficients without system restart
FILEEOF

cat > "$CORP_MNT/Legal/nda_counterparty_delta.txt" << 'FILEEOF'
MUTUAL NON-DISCLOSURE AGREEMENT
Between: ACME Corp ("Disclosing Party")
And: Delta Automotive GmbH ("Receiving Party")
Effective Date: February 1, 2024
Expiration: January 31, 2027

PURPOSE: Evaluation of ACME sensor modules for integration into Delta
Automotive's next-generation ADAS (Advanced Driver Assistance Systems)
platform, code-named "Project Falcon."

CONFIDENTIAL INFORMATION includes but is not limited to:
  - Circuit schematics and PCB layouts
  - Firmware source code and algorithms
  - Calibration data and test results
  - Pricing and volume discount schedules
  - Roadmap and unreleased product specifications
FILEEOF

cat > "$CORP_MNT/Legal/litigation_timeline.txt" << 'FILEEOF'
Active Litigation Timeline - ACME Corp
Last Updated: 2024-03-01
Counsel: Baker & McKenzie LLP

Case 1: ACME v. SensorTech Inc. (Patent Infringement)
  Filed: 2023-06-15, USDC Northern District of California
  Status: Discovery phase, depositions scheduled Q2 2024
  Damages sought: $12.5M + injunctive relief
  Next deadline: Expert reports due 2024-05-15

Case 2: GlobalChip LLC v. ACME (Trade Secret Misappropriation)
  Filed: 2023-11-20, USDC Delaware
  Status: Motion to dismiss pending (hearing 2024-04-10)
  Exposure: $8.0M (counsel estimates 30% likelihood of adverse ruling)
FILEEOF

cat > "$CORP_MNT/Legal/regulatory_compliance.txt" << 'FILEEOF'
Regulatory Compliance Status Report - Q1 2024

CE Marking (EU):
  Product: IoT Sensor Hub v3 (Model: ACME-ISH-300)
  Directive: 2014/30/EU (EMC), 2014/35/EU (LVD), 2014/53/EU (RED)
  Testing Lab: Bureau Veritas (Shenzhen Lab #CN-SZ-042)
  Status: PASS - Certificate issued 2024-02-28
  Certificate No: CE-2024-ACME-ISH300-001

FCC Part 15 (US):
  FCC ID: 2A4XMISH300
  Status: Grant issued 2024-01-15
  Modular approval: Yes (single-module transmitter)

UL 62368-1 (Safety):
  Status: Testing in progress, ETA 2024-04-30
FILEEOF

cat > "$CORP_MNT/Legal/trademark_filing.txt" << 'FILEEOF'
Trademark Application Status
IP Counsel: J. Morrison, Baker & McKenzie

Mark: ACME SENSEFUSION (Wordmark)
  Application No: 97/654,321
  Filing Date: 2024-01-10
  Class: 009 (Electronic sensors, IoT devices)
  Status: Published for opposition (OG date: 2024-04-02)

Mark: ACME (Stylized Logo - Hexagonal sensor icon)
  Registration No: 6,789,012
  Renewal Due: 2029-08-15
  Status: Active, in use (specimens filed 2023)
FILEEOF

cat > "$CORP_MNT/Legal/settlement_terms.txt" << 'FILEEOF'
CONFIDENTIAL - ATTORNEY-CLIENT PRIVILEGED
Settlement Discussion Summary
Case: GlobalChip LLC v. ACME Corp

Proposed Terms (Counter-offer #3):
  - ACME pays $1.2M lump sum (vs GlobalChip demand of $8.0M)
  - Cross-license agreement for patents US10,123,456 and US10,234,567
  - Non-admission of liability clause
  - Mutual release of all related claims
  - 18-month non-compete on specific product category (environmental sensors)

Counsel recommendation: Accept if GlobalChip agrees to $1.5M cap.
Board approval required for any amount exceeding $1.0M.
FILEEOF

# ── Research files (6 files) ──
cat > "$CORP_MNT/Research/experiment_log_042.txt" << 'FILEEOF'
Experiment Log #042 - Advanced Materials Lab
Principal Investigator: Dr. Raj Patel
Date Range: 2024-02-05 to 2024-02-16

Objective: Evaluate graphene-oxide thin film as humidity sensor substrate

Trial 042-A (Feb 5):
  Substrate: GO film 150nm on SiO2/Si wafer
  Deposition: Spray coating, 5 passes @ 80C
  Response: 12.3% capacitance change at 30-90% RH
  Hysteresis: 4.1% (target < 3%)
  Recovery time: 8.2s (target < 5s)

Trial 042-B (Feb 9):
  Substrate: Reduced GO (rGO) film 120nm
  Deposition: Same as 042-A + UV reduction 30min
  Response: 8.7% capacitance change (reduced sensitivity)
  Hysteresis: 1.8% (WITHIN TARGET)
  Recovery time: 3.4s (WITHIN TARGET)
  NOTE: rGO shows promise - schedule follow-up with thicker films

Trial 042-C (Feb 16):
  Substrate: rGO 200nm with PDMS encapsulation
  Response: 10.1% (improved vs 042-B)
  Hysteresis: 2.2% (WITHIN TARGET)
  Recovery time: 4.1s (WITHIN TARGET)
  CONCLUSION: Proceed to prototype integration (Project Nimbus)
FILEEOF

cat > "$CORP_MNT/Research/compound_analysis.csv" << 'FILEEOF'
compound_id,formula,molecular_weight,melting_point_c,solubility_g_l,application,status,researcher
AC-2024-001,C8H12N2O3,184.19,127.3,23.4,Polymer crosslinker,Active,R.Patel
AC-2024-002,C12H18Si2O4,286.43,89.6,0.8,Hydrophobic coating,Discontinued,R.Patel
AC-2024-003,C6H10N4O2,170.17,203.1,145.0,Sensor substrate binder,Active,J.Hayes
AC-2024-004,C15H22O6,298.33,112.4,12.7,Flexible PCB adhesive,Testing,K.Park
AC-2024-005,C9H14N2O5S,278.28,156.8,67.3,Conductive polymer dopant,Active,J.Hayes
AC-2024-006,C11H16O3Si,224.32,78.2,3.2,Surface functionalization,Evaluation,R.Patel
FILEEOF

cat > "$CORP_MNT/Research/trial_results_batch_7.txt" << 'FILEEOF'
Environmental Sensor Trial Results - Batch 7
Project: Nimbus (Next-gen Humidity Sensor)
Test Engineer: Jordan Hayes
Date: 2024-03-01

Unit SN-B7-001:
  Accuracy: +/- 1.2% RH (spec: +/- 2%)    PASS
  Response time (10-90%): 3.8s (spec: < 5s) PASS
  Power consumption: 142uA (spec: < 200uA)  PASS
  Operating range: -10C to +65C              PASS

Unit SN-B7-002:
  Accuracy: +/- 1.8% RH                     PASS
  Response time: 4.2s                        PASS
  Power consumption: 138uA                   PASS
  Operating range: -10C to +65C              PASS

Unit SN-B7-003:
  Accuracy: +/- 3.1% RH                     FAIL (exceeds spec)
  Response time: 6.7s                        FAIL
  Root cause: Suspected GO film delamination during thermal cycling
  Disposition: Quarantine for failure analysis

Batch yield: 2/3 = 66.7% (target: 90%)
Action: Review deposition process parameters with manufacturing
FILEEOF

cat > "$CORP_MNT/Research/grant_proposal.txt" << 'FILEEOF'
NSF SBIR Phase II Proposal
Title: Graphene-Based Multi-Parameter Environmental Sensor Array
PI: Dr. Raj Patel, ACME Corp
Requested Amount: $1,000,000
Period: 24 months

Technical Abstract:
This proposal builds on our Phase I findings demonstrating graphene-oxide
thin films as viable humidity sensing substrates with sub-3% hysteresis.
Phase II will develop a monolithic sensor array combining humidity,
temperature, pressure, and VOC detection on a single 5mm x 5mm die.

The key innovation is our patent-pending adaptive calibration algorithm
(provisional patent 63/456,789) that achieves NIST-traceable accuracy
without factory calibration, reducing per-unit cost by an estimated 60%.
FILEEOF

cat > "$CORP_MNT/Research/lab_safety_protocol.txt" << 'FILEEOF'
Laboratory Safety Protocol - Advanced Materials Lab
Effective: January 1, 2024
Safety Officer: T. Williams

Chemical Handling:
  - All graphene-oxide dispersions: handle in fume hood, nitrile gloves
  - Hydrazine (reducing agent): double gloves, face shield, buddy system
  - Waste: segregated containers labeled per RCRA guidelines

Equipment:
  - UV exposure system: interlock-verified before each use
  - Spin coater: maximum 6000 RPM, secure lid before operation
  - Tube furnace: never exceed 800C without PI approval

Emergency:
  - Chemical spill kit: Cabinet B-12 (renewed quarterly)
  - Eye wash station: 15-second flush minimum
  - Emergency contacts posted at each exit
FILEEOF

cat > "$CORP_MNT/Research/reagent_inventory.csv" << 'FILEEOF'
reagent_id,name,cas_number,quantity_ml,location,expiry_date,hazard_class,custodian
RG-001,Graphene Oxide Dispersion (4mg/mL),7782-42-5,500,Fume Hood A3,2025-06-30,Irritant,R.Patel
RG-002,Hydrazine Monohydrate 98%,7803-57-8,100,Flammable Cabinet C1,2024-12-31,Toxic/Flammable,R.Patel
RG-003,PDMS (Sylgard 184 Base),63148-62-9,1000,Shelf B2,2025-03-15,None,K.Park
RG-004,N-Methyl-2-Pyrrolidone (NMP),872-50-4,250,Fume Hood A3,2025-01-31,Reproductive Toxin,J.Hayes
RG-005,Isopropyl Alcohol 99.5%,67-63-0,2500,Flammable Cabinet C1,2025-09-30,Flammable,T.Williams
RG-006,Silver Nanoparticle Ink,7440-22-4,50,Refrigerator R1 (4C),2024-08-15,Environmental Hazard,J.Hayes
FILEEOF

# ── Executive files (6 files) ──
cat > "$CORP_MNT/Executive/board_strategy_2025.txt" << 'FILEEOF'
ACME Corp - Board Strategic Plan FY2025
Classification: BOARD CONFIDENTIAL
Presented: Board Meeting #2024-Q1-003

Strategic Pillars:
1. AUTOMOTIVE EXPANSION
   - Target 3 new Tier-1 partnerships (current pipeline: Delta, Bosch, Continental)
   - Revenue target from automotive: $35M (up from $12M in FY2024)
   - ADAS sensor qualification by Q2 2025

2. PLATFORM PLAY
   - Launch SenseFusion Cloud platform (SaaS recurring revenue model)
   - Target: 500 enterprise accounts by end FY2025
   - ARR goal: $8M

3. INORGANIC GROWTH
   - Acquire complementary sensor technology company
   - Budget: $15-25M (funded from Series C proceeds)
   - Priority targets: NanoSense Ltd (UK), Photon Dynamics (Israel)

Board approval requested for $2M due diligence budget.
FILEEOF

cat > "$CORP_MNT/Executive/acquisition_target_list.txt" << 'FILEEOF'
M&A Target Assessment - CONFIDENTIAL
Prepared by: Corporate Development, February 2024

TARGET 1: NanoSense Ltd (Cambridge, UK)
  Technology: MEMS pressure sensors, patented vacuum packaging
  Revenue: $8.2M (FY2023), growing 25% YoY
  Employees: 47
  Estimated valuation: $18-22M (4-5x revenue)
  Strategic fit: HIGH (fills pressure sensing gap in our portfolio)
  Risk: Brexit-related IP jurisdiction complexity

TARGET 2: Photon Dynamics Inc (Tel Aviv, Israel)
  Technology: LiDAR-on-chip, solid-state optical sensors
  Revenue: $3.1M (pre-revenue, mostly grants + pilot contracts)
  Employees: 23
  Estimated valuation: $12-15M (technology premium)
  Strategic fit: MEDIUM (adjacent to core, enables new markets)
  Risk: Early-stage technology, key-person dependence on 2 founders
FILEEOF

cat > "$CORP_MNT/Executive/executive_compensation.csv" << 'FILEEOF'
exec_id,name,title,base_salary_usd,bonus_target_pct,equity_shares,hire_date,review_date
C-001,Michael Torres,CEO,425000,50,150000,2018-03-01,2024-03-01
C-002,Diana Morrison,CFO,340000,40,80000,2019-07-15,2024-07-15
C-003,James Liu,CTO,380000,45,120000,2017-11-01,2024-11-01
C-004,Amanda Foster,VP Sales,290000,60,45000,2020-02-01,2024-02-01
C-005,Robert Singh,VP Engineering,310000,35,65000,2019-01-15,2024-01-15
FILEEOF

cat > "$CORP_MNT/Executive/market_analysis.txt" << 'FILEEOF'
IoT Sensor Market Analysis - 2024 Update
Source: Internal analysis + IDC/Gartner data

Total Addressable Market (TAM):
  Global IoT Sensor Market 2024: $38.7B
  CAGR 2024-2029: 12.4%
  Projected 2029: $69.8B

ACME Serviceable Market (SAM):
  Industrial + Automotive + Environmental: $12.3B
  ACME market share (2023): 0.8% ($98.5M revenue / $12.3B SAM)
  Target market share (2026): 1.5% (~$220M revenue)

Key Growth Drivers:
  - Smart building regulations (EU Energy Performance Directive)
  - Automotive ADAS sensor proliferation (L2+ autonomy)
  - Industrial IoT predictive maintenance adoption
  - Air quality monitoring mandates (EPA/WHO guidelines)
FILEEOF

cat > "$CORP_MNT/Executive/org_restructuring.txt" << 'FILEEOF'
Organization Restructuring Proposal - DRAFT
For CEO Review Only

Proposed Changes (effective Q3 2024):
1. Merge "Advanced Materials Lab" into Engineering (eliminate Research as standalone)
   - Dr. Patel reports to CTO instead of CEO
   - Saves 2 director-level positions ($680K annual)

2. Create "Automotive Business Unit" (new)
   - GM: External hire (budget: $280K base + equity)
   - Transfer 8 engineers from core product team
   - Dedicated P&L by Q4 2024

3. Outsource IT infrastructure to managed services provider
   - Estimated savings: $1.2M annually
   - Retain 3 in-house security staff for SOC operations
   - RFP to be issued by April 15, 2024
FILEEOF

cat > "$CORP_MNT/Executive/investor_relations.txt" << 'FILEEOF'
Investor Update - Q4 2023 / Q1 2024
Prepared for: Series B Investors (Sequoia, Accel, Khosla)

Financial Highlights:
  FY2023 Revenue: $168.4M (+22% YoY)
  Gross Margin: 61.3% (up from 58.7%)
  Cash Position: $34.2M (post Series B)
  Burn Rate: $2.1M/month (22-month runway at current burn)

Series C Planning:
  Target raise: $40-50M
  Timing: Q3 2024
  Lead investor discussions: Andreessen Horowitz (strong interest),
    Tiger Global (preliminary), SoftBank Vision Fund (declined)

Use of Funds:
  - 40% M&A (sensor technology acquisition)
  - 30% Automotive market expansion
  - 20% SenseFusion Cloud platform development
  - 10% Working capital
FILEEOF

sync
umount "$CORP_MNT"
rmdir "$CORP_MNT"
echo "Corporate repository image created: $CORP_IMG ($(stat -c%s "$CORP_IMG") bytes)"

# ── Create Suspect USB Image (16MB NTFS) ─────────────────────────────────────
USB_IMG="/home/ga/evidence/suspect_usb.dd"
USB_MNT="/tmp/mnt_suspect_usb"

echo "Creating suspect USB NTFS image..."
dd if=/dev/zero of="$USB_IMG" bs=1M count=16 2>/dev/null
mkfs.ntfs -F -q -L "JORDAN_USB" "$USB_IMG"

mkdir -p "$USB_MNT"
if ! mount -t ntfs-3g -o loop,streams_interface=xattr "$USB_IMG" "$USB_MNT"; then
    echo "ERROR: Failed to mount USB image"
    exit 1
fi

mkdir -p "$USB_MNT/Documents"
mkdir -p "$USB_MNT/Projects"

# ── Exact copies of 8 corporate files (same content = same MD5) ──
# These are the "exfiltrated" files
cp "$CORP_IMG" /dev/null 2>/dev/null  # Just to ensure it still exists

# We need to remount corporate to copy files
CORP_MNT2="/tmp/mnt_corp_repo2"
mkdir -p "$CORP_MNT2"
mount -t ntfs-3g -o loop,ro "$CORP_IMG" "$CORP_MNT2"

# 8 exact copies (exfiltrated)
cp "$CORP_MNT2/Engineering/circuit_design_v3.txt"   "$USB_MNT/Documents/"
cp "$CORP_MNT2/Engineering/firmware_specs.txt"       "$USB_MNT/Documents/"
cp "$CORP_MNT2/Finance/revenue_forecast_2024.txt"    "$USB_MNT/Documents/"
cp "$CORP_MNT2/Legal/patent_draft_2024_001.txt"      "$USB_MNT/Documents/"
cp "$CORP_MNT2/Research/compound_analysis.csv"       "$USB_MNT/Projects/"
cp "$CORP_MNT2/Executive/board_strategy_2025.txt"    "$USB_MNT/Documents/"
cp "$CORP_MNT2/Executive/acquisition_target_list.txt" "$USB_MNT/Documents/"
cp "$CORP_MNT2/Executive/executive_compensation.csv" "$USB_MNT/Documents/"

# 3 modified copies (same filename, appended content = different MD5)
cp "$CORP_MNT2/Engineering/sensor_calibration.csv" "$USB_MNT/Projects/sensor_calibration.csv"
echo "SN-2024-0004,CH0,0.612,1.00044,5.3,2024-03-20,J.Hayes" >> "$USB_MNT/Projects/sensor_calibration.csv"
echo "SN-2024-0004,CH1,-0.198,0.99961,6.1,2024-03-20,J.Hayes" >> "$USB_MNT/Projects/sensor_calibration.csv"

cp "$CORP_MNT2/Research/trial_results_batch_7.txt" "$USB_MNT/Projects/trial_results_batch_7.txt"
cat >> "$USB_MNT/Projects/trial_results_batch_7.txt" << 'APPENDEOF'

ADDENDUM (added by J.Hayes, not in official record):
Unit SN-B7-003 failure analysis suggests manufacturing defect, not design.
Recommend proceeding to production despite 66.7% yield. The delamination
can be mitigated with a thicker PDMS layer (300nm vs current 200nm).
APPENDEOF

cp "$CORP_MNT2/Executive/market_analysis.txt" "$USB_MNT/Documents/market_analysis.txt"
cat >> "$USB_MNT/Documents/market_analysis.txt" << 'APPENDEOF'

--- PERSONAL NOTES (J.Hayes) ---
CompetitorCorp is targeting the same automotive ADAS market. Their pitch
deck claims 15% better sensitivity than ACME's current gen. Need to verify
this independently before my meeting with their VP Engineering on March 20.
APPENDEOF

# Files that will be deleted (create then remove before unmount)
cp "$CORP_MNT2/Finance/vendor_payments_q3.csv"    "$USB_MNT/vendor_payments_q3.csv"
cp "$CORP_MNT2/Research/experiment_log_042.txt"    "$USB_MNT/experiment_log_042.txt"

cat > "$USB_MNT/personal_notes.txt" << 'FILEEOF'
Job search notes - DO NOT LEAVE ON WORK LAPTOP
- CompetitorCorp: VP Sensor Engineering role, $350K + equity
- Interview scheduled: March 20, 2024
- They want someone with sensor fusion expertise
- Bring portfolio of work samples (sanitized?)
FILEEOF

cat > "$USB_MNT/job_applications.txt" << 'FILEEOF'
Application Tracker:
1. CompetitorCorp - VP Sensor Engineering - APPLIED 2024-02-15 - PHONE SCREEN DONE
2. MegaSensor Inc - Director R&D - APPLIED 2024-02-20 - NO RESPONSE
3. QuantumSense AI - CTO - APPLIED 2024-03-01 - FIRST ROUND SCHEDULED
FILEEOF

cat > "$USB_MNT/usb_transfer_log.txt" << 'FILEEOF'
Transfer log (auto-generated):
2024-03-10 22:14:07 COPY circuit_design_v3.txt -> /Documents/
2024-03-10 22:14:08 COPY firmware_specs.txt -> /Documents/
2024-03-10 22:14:09 COPY revenue_forecast_2024.txt -> /Documents/
2024-03-10 22:14:10 COPY patent_draft_2024_001.txt -> /Documents/
2024-03-10 22:14:11 COPY compound_analysis.csv -> /Projects/
2024-03-10 22:14:12 COPY board_strategy_2025.txt -> /Documents/
2024-03-10 22:14:13 COPY acquisition_target_list.txt -> /Documents/
2024-03-10 22:14:14 COPY executive_compensation.csv -> /Documents/
FILEEOF

umount "$CORP_MNT2"
rmdir "$CORP_MNT2"

# Now delete the files that should appear as "deleted" on the USB
rm "$USB_MNT/vendor_payments_q3.csv"
rm "$USB_MNT/experiment_log_042.txt"
rm "$USB_MNT/personal_notes.txt"
rm "$USB_MNT/job_applications.txt"
rm "$USB_MNT/usb_transfer_log.txt"

# ── Inject NTFS Alternate Data Streams ──
echo "Injecting ADS into USB image..."
python3 << 'PYEOF'
import os

mnt = "/tmp/mnt_suspect_usb"

# ADS 1: transfer_log stream on circuit_design_v3.txt
f1 = os.path.join(mnt, "Documents", "circuit_design_v3.txt")
ads1_content = b"Copied via USB3.0 hub at 22:14 UTC 2024-03-10\nSource: //CORP-NAS/Engineering/designs/\nDuration: 0.8 seconds"
os.setxattr(f1, "user.transfer_log", ads1_content)

# ADS 2: notes stream on board_strategy_2025.txt
f2 = os.path.join(mnt, "Documents", "board_strategy_2025.txt")
ads2_content = b"Review before CompetitorCorp interview on March 20\nKey points: automotive expansion, M&A targets, platform strategy"
os.setxattr(f2, "user.notes", ads2_content)

# ADS 3: source_path stream on compound_analysis.csv
f3 = os.path.join(mnt, "Projects", "compound_analysis.csv")
ads3_content = b"Original location: //CORP-NAS/Research/Active/Project_Nimbus/\nAccessed: 2024-03-10 21:58 UTC"
os.setxattr(f3, "user.source_path", ads3_content)

print("ADS injection complete:")
print(f"  {f1}:transfer_log ({len(ads1_content)} bytes)")
print(f"  {f2}:notes ({len(ads2_content)} bytes)")
print(f"  {f3}:source_path ({len(ads3_content)} bytes)")
PYEOF

sync
umount "$USB_MNT"
rmdir "$USB_MNT"
echo "Suspect USB image created: $USB_IMG ($(stat -c%s "$USB_IMG") bytes)"

# ── Generate Corporate Hash Inventory + Ground Truth ─────────────────────────
echo "Generating corporate hash inventory and ground truth..."
python3 << 'PYEOF'
import subprocess, json, hashlib, os, re

CORP_IMG = "/home/ga/evidence/corporate_repo.dd"
USB_IMG = "/home/ga/evidence/suspect_usb.dd"

def get_files_with_hashes(image_path, include_deleted=False):
    """Extract all files from an image with their MD5 hashes using TSK tools."""
    result = subprocess.run(["fls", "-r", "-p", image_path],
                            capture_output=True, text=True, timeout=60)
    files = []
    for line in result.stdout.splitlines():
        is_deleted = " * " in line
        if not include_deleted and is_deleted:
            continue

        # Parse fls output: type inode[-...]:  path
        m = re.match(r'([rd/\-+\*\s]+)\s*(\d+)(?:-\S+)?:\s+(.+)', line.strip())
        if not m:
            continue

        type_field = m.group(1).strip()
        inode = m.group(2)
        name = m.group(3).strip()

        # Skip directories, system files, ADS
        if '/d' in type_field and '/r' not in type_field:
            continue
        if name.startswith('$') or name in ('.', '..'):
            continue
        # ADS entries contain ':'
        if ':' in name and not name.startswith('/'):
            continue

        # Get file content and compute MD5
        try:
            icat_result = subprocess.run(["icat", image_path, inode],
                                         capture_output=True, timeout=10)
            if icat_result.returncode == 0 and len(icat_result.stdout) > 0:
                md5 = hashlib.md5(icat_result.stdout).hexdigest()
                size = len(icat_result.stdout)
                basename = os.path.basename(name)
                files.append({
                    "name": basename,
                    "path": name,
                    "inode": inode,
                    "md5": md5,
                    "size": size,
                    "deleted": is_deleted
                })
        except Exception:
            pass
    return files

def get_ads_entries(image_path):
    """Find ADS entries using fls."""
    result = subprocess.run(["fls", "-r", "-p", image_path],
                            capture_output=True, text=True, timeout=60)
    ads_entries = []
    for line in result.stdout.splitlines():
        # ADS shows as: r/r inode:  path/file:stream_name
        if ':' not in line:
            continue
        m = re.match(r'([rd/\-+\*\s]+)\s*(\d+(?:-\d+-\d+)?):\s+(.+)', line.strip())
        if not m:
            continue
        full_path = m.group(3).strip()
        inode_full = m.group(2)  # e.g. "71-128-4" for ADS attribute
        # Check if this is an ADS (contains : in the filename part, not in path prefix)
        parts = full_path.rsplit(':', 1)
        if len(parts) == 2:
            host_path = parts[0]
            stream_name = parts[1]
            # Skip NTFS system streams
            if stream_name.startswith('$') or host_path.startswith('$'):
                continue
            host_basename = os.path.basename(host_path)
            # Get stream size
            try:
                icat_result = subprocess.run(["icat", image_path, inode_full],
                                             capture_output=True, timeout=10)
                stream_size = len(icat_result.stdout)
            except Exception:
                stream_size = 0
            ads_entries.append({
                "host_file": host_basename,
                "stream_name": stream_name,
                "stream_size": stream_size
            })
    return ads_entries

# Get corporate files
corp_files = get_files_with_hashes(CORP_IMG, include_deleted=False)
corp_md5_map = {f["md5"]: f for f in corp_files}
corp_name_map = {f["name"]: f for f in corp_files}

# Get USB files (allocated)
usb_allocated = get_files_with_hashes(USB_IMG, include_deleted=False)

# Get USB deleted files
all_usb = get_files_with_hashes(USB_IMG, include_deleted=True)
usb_deleted = [f for f in all_usb if f["deleted"]]

# Get ADS
usb_ads = get_ads_entries(USB_IMG)

# Cross-reference: exfiltrated (same MD5 on both)
exfiltrated = []
for uf in usb_allocated:
    if uf["md5"] in corp_md5_map:
        cf = corp_md5_map[uf["md5"]]
        exfiltrated.append({
            "usb_filename": uf["name"],
            "usb_path": uf["path"],
            "md5": uf["md5"],
            "file_size": uf["size"],
            "corp_path": cf["path"],
            "corp_department": cf["path"].split("/")[0] if "/" in cf["path"] else "Unknown"
        })

# Cross-reference: modified (same name, different MD5)
modified = []
for uf in usb_allocated:
    if uf["name"] in corp_name_map:
        cf = corp_name_map[uf["name"]]
        if uf["md5"] != cf["md5"]:
            modified.append({
                "filename": uf["name"],
                "usb_md5": uf["md5"],
                "corporate_md5": cf["md5"],
                "usb_size": uf["size"]
            })

# Department tally for most-targeted
dept_counts = {}
for ef in exfiltrated:
    dept = ef["corp_department"]
    dept_counts[dept] = dept_counts.get(dept, 0) + 1
for mf in modified:
    if mf["filename"] in corp_name_map:
        cf = corp_name_map[mf["filename"]]
        dept = cf["path"].split("/")[0] if "/" in cf["path"] else "Unknown"
        dept_counts[dept] = dept_counts.get(dept, 0) + 1

most_targeted = max(dept_counts, key=dept_counts.get) if dept_counts else "Unknown"

# Write corporate hashes file (for agent to import as hash set)
with open("/home/ga/evidence/corporate_hashes.txt", "w") as hf:
    for cf in corp_files:
        hf.write(f"{cf['md5']}  {cf['name']}\n")

# Build ground truth
gt = {
    "corporate_files": corp_files,
    "exfiltrated": exfiltrated,
    "modified": modified,
    "deleted": [{"name": d["name"], "size": d["size"], "md5": d["md5"]} for d in usb_deleted],
    "ads": usb_ads,
    "summary": {
        "exfiltrated_count": len(exfiltrated),
        "modified_count": len(modified),
        "deleted_count": len(usb_deleted),
        "concealed_count": len(usb_ads),
        "most_targeted_department": most_targeted,
        "risk": "HIGH"
    }
}

with open("/tmp/exfiltration_gt.json", "w") as f:
    json.dump(gt, f, indent=2)
os.chmod("/tmp/exfiltration_gt.json", 0o600)

print(f"Corporate files: {len(corp_files)}")
print(f"Exfiltrated (MD5 match): {len(exfiltrated)}")
print(f"Modified (name match, MD5 diff): {len(modified)}")
print(f"Deleted on USB: {len(usb_deleted)}")
print(f"ADS on USB: {len(usb_ads)}")
print(f"Most targeted department: {most_targeted}")
print(f"Corporate hashes written: {len(corp_files)} entries")

PYEOF

chown ga:ga /home/ga/evidence/corporate_hashes.txt
chown ga:ga /home/ga/evidence/corporate_repo.dd
chown ga:ga /home/ga/evidence/suspect_usb.dd
chmod 644 /home/ga/evidence/corporate_hashes.txt
chmod 644 /home/ga/evidence/corporate_repo.dd
chmod 644 /home/ga/evidence/suspect_usb.dd

# ── Record task start time (AFTER cleaning, BEFORE launching app) ─────────────
date +%s > /tmp/exfiltration_start_time

# ── Kill any old Autopsy and launch fresh ─────────────────────────────────────
kill_autopsy

echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

# Wait for Welcome window and dismiss any dialogs
WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected after ${WELCOME_ELAPSED}s"
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

take_screenshot /tmp/task_initial_state.png
echo "=== Setup complete ==="
