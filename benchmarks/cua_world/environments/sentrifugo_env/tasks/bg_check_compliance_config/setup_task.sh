#!/bin/bash
echo "=== Setting up bg_check_compliance_config task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Ensure a clean slate for the specific entities to avoid false positives from previous runs
# We use broad DELETE queries matching keywords from the expected entries
docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -e \
    "DELETE FROM main_bgscreeningtype WHERE bgscreeningtype LIKE '%Drug%' OR bgscreeningtype LIKE '%Criminal%' OR bgscreeningtype LIKE '%Credential%' OR bgscreeningtype LIKE '%License%' OR bgscreeningtype LIKE '%Safety%';" 2>/dev/null || true

docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -e \
    "DELETE FROM main_bgagencylist WHERE agencyname LIKE '%NationalScreen%' OR agencyname LIKE '%VerifyFirst%' OR agencyname LIKE '%SafeHire%';" 2>/dev/null || true

# Record initial counts
INITIAL_TYPES=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -e "SELECT COUNT(*) FROM main_bgscreeningtype" 2>/dev/null || echo "0")
INITIAL_AGENCIES=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -e "SELECT COUNT(*) FROM main_bgagencylist" 2>/dev/null || echo "0")
echo "$INITIAL_TYPES" > /tmp/initial_types_count
echo "$INITIAL_AGENCIES" > /tmp/initial_agencies_count

# Create the compliance directive document on the Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/doe_screening_directive.txt << 'EOF'
═══════════════════════════════════════════════════════════════
       U.S. DEPARTMENT OF ENERGY — COMPLIANCE DIRECTIVE
       Office of Environment, Health, Safety and Security
       Directive No. DOE-EHSS-2026-0041
       Effective Date: February 1, 2026
═══════════════════════════════════════════════════════════════

SUBJECT: Mandatory Background Screening Requirements for
         Personnel at Biomass Energy Conversion Facilities

AUTHORITY: 10 CFR 851 — Worker Safety and Health Program
           DOE Order 472.2 — Personnel Security

TO: All Biomass Power Plant Site Managers

───────────────────────────────────────────────────────────────
SECTION 1: REQUIRED SCREENING TYPES
───────────────────────────────────────────────────────────────

All facilities must configure the following screening categories
in their Human Resource Management System (HRMS) for tracking
and audit purposes:

  1. Drug & Substance Screening
     - Required for all personnel with access to operational areas
     - Includes DOT 5-panel and expanded 10-panel protocols

  2. Criminal Background Check
     - County, state, and federal criminal history search
     - Required for all new hires and transfers

  3. Education & Credential Verification
     - Verification of degrees, diplomas, and certifications
     - Required for all engineering and technical positions

  4. Professional License Verification
     - State and national license validation
     - Required for licensed engineers, operators, and technicians

  5. Safety Certification Compliance
     - OSHA 10/30, HAZWOPER, confined space, and fall protection
     - Required for all field and maintenance personnel

───────────────────────────────────────────────────────────────
SECTION 2: APPROVED SCREENING VENDOR AGENCIES
───────────────────────────────────────────────────────────────

The following agencies have been pre-approved under DOE Master
Agreement DA-2026-BG-003. Configure each in your HRMS:

  Agency 1: NationalScreen Inc.
    Phone:   (800) 555-0147
    Website: www.nationalscreen-inc.com

  Agency 2: VerifyFirst Solutions
    Phone:   (888) 555-0233
    Website: www.verifyfirstsolutions.com

  Agency 3: SafeHire Compliance Group
    Phone:   (877) 555-0391
    Website: www.safehirecompliance.com

───────────────────────────────────────────────────────────────
SECTION 3: COMPLIANCE TIMELINE
───────────────────────────────────────────────────────────────

All screening types and agency configurations must be completed
in the HRMS prior to the next hiring cycle. Failure to comply
may result in suspension of operating license per 10 CFR 851.7.

Signed,
Dr. Margaret Thornton
Deputy Assistant Secretary for Safety
U.S. Department of Energy
EOF

chown ga:ga /home/ga/Desktop/doe_screening_directive.txt

# Start Firefox and navigate to the dashboard
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 5

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="