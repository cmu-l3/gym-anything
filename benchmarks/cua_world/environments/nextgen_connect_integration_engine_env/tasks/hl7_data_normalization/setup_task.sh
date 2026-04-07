#!/bin/bash
echo "=== Setting up HL7 Data Normalization Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Create directories
mkdir -p /tmp/test_hl7_messages
mkdir -p /tmp/normalized_output
chmod 777 /tmp/test_hl7_messages /tmp/normalized_output
chown -R ga:ga /tmp/test_hl7_messages /tmp/normalized_output

# 2. Generate Messy Test Data
# We use printf to ensure correct \r delimiters for HL7
echo "Generating test messages..."

# Hospital A: Mostly correct, checking pass-through and minor formatting
# Phone: (555) 867-5309, DOB: 19850315, Gender: M
printf "MSH|^~\\&|HOSP_A|ADT|RECEIVER|ADT|20230101000000||ADT^A04|MSG001|P|2.3\rEVN|A04|20230101000000\rPID|1||10001^^^HOSP_A||DOE^JOHN^^^^||19850315|M|||123 MAIN ST^^BOSTON^MA^02110||(555) 867-5309||||||||\rPV1|1|O|\r" > /tmp/test_hl7_messages/hospital_a.hl7

# Hospital B: Dots in phone, Slashes in DOB, Full word Gender
# Phone: 555.234.5678, DOB: 03/22/1990, Gender: Female
printf "MSH|^~\\&|HOSP_B|ADT|RECEIVER|ADT|20230101000000||ADT^A04|MSG002|P|2.3\rEVN|A04|20230101000000\rPID|1||10002^^^HOSP_B||SMITH^JANE^^^^||03/22/1990|Female|||456 OAK AVE^^NEWYORK^NY^10001||555.234.5678||||||||\rPV1|1|O|\r" > /tmp/test_hl7_messages/hospital_b.hl7

# Hospital C: Raw digits phone, Dashes in DOB, Numeric Gender
# Phone: 5559876543, DOB: 1978-11-05, Gender: 1 (Male)
printf "MSH|^~\\&|HOSP_C|ADT|RECEIVER|ADT|20230101000000||ADT^A04|MSG003|P|2.3\rEVN|A04|20230101000000\rPID|1||10003^^^HOSP_C||BROWN^BOB^^^^||1978-11-05|1|||789 PINE LN^^CHICAGO^IL^60601||5559876543||||||||\rPV1|1|O|\r" > /tmp/test_hl7_messages/hospital_c.hl7

# Hospital D: Country code phone, Single digit month/day, Uppercase Gender
# Phone: 1-555-345-6789, DOB: 7/4/2001, Gender: MALE
printf "MSH|^~\\&|HOSP_D|ADT|RECEIVER|ADT|20230101000000||ADT^A04|MSG004|P|2.3\rEVN|A04|20230101000000\rPID|1||10004^^^HOSP_D||WHITE^JAMES^^^^||7/4/2001|MALE|||321 ELM ST^^SEATTLE^WA^98101||1-555-345-6789||||||||\rPV1|1|O|\r" > /tmp/test_hl7_messages/hospital_d.hl7

chown ga:ga /tmp/test_hl7_messages/*.hl7

# 3. Record Initial State
INITIAL_CHANNEL_COUNT=$(get_channel_count)
echo "$INITIAL_CHANNEL_COUNT" > /tmp/initial_channel_count
date +%s > /tmp/task_start_time

# 4. Open Terminal for Agent
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - Data Normalization Task"
echo "============================================"
echo ""
echo "GOAL: Create channel \"Data_Quality_Normalizer\""
echo "  - Source: TCP Listener port 6661"
echo "  - Destination: File Writer to /tmp/normalized_output/"
echo ""
echo "TRANSFORMATION REQUIREMENTS (JavaScript):"
echo "  1. Phone (PID-13): Format as (XXX) XXX-XXXX"
echo "  2. DOB (PID-7): Format as YYYYMMDD"
echo "  3. Gender (PID-8): Standardize to M, F, O, or U"
echo ""
echo "TEST DATA:"
echo "  - Input: /tmp/test_hl7_messages/ (4 files)"
echo "  - Send using: nc localhost 6661 or Mirth Connect Administrator"
echo ""
echo "ACCESS:"
echo "  - API: https://localhost:8443/api (admin/admin)"
echo "  - Web: https://localhost:8443"
echo "============================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

echo "=== Setup Complete ==="