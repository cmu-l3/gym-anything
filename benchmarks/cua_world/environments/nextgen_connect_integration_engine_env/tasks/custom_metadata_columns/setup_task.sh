#!/bin/bash
echo "=== Setting up custom_metadata_columns task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Create test data files
echo "Creating test HL7 messages..."

# Message 1: ADT^A01
cat > /home/ga/adt_a01.hl7 <<EOF
MSH|^~\&|EPIC|MAIN_HOSP|NEXTGEN|HIS|20240115103000||ADT^A01^ADT_A01|MSG00001|P|2.5.1|||AL|NE
EVN|A01|20240115103000
PID|1||MRN78432^^^MAIN_HOSP^MR||JOHNSON^ROBERT^T||19620714|M|||456 Oak Avenue^^Chicago^IL^60601||3125550142|||M|NON|400123456
PV1|1|I|ICU^0301^01||||1234^SMITH^SARAH^J^^^MD|5678^WILLIAMS^MARIA^L^^^MD||MED||||ADM|A0||||||||||||||||||||||||||20240115103000
IN1|1|BCBS001|BCBS Illinois|Blue Cross Blue Shield|||||||19900101||||JOHNSON^ROBERT^T|SELF|19620714|456 Oak Avenue^^Chicago^IL^60601
EOF

# Message 2: ADT^A04
cat > /home/ga/adt_a04.hl7 <<EOF
MSH|^~\&|CERNER|SOUTH_CLINIC|NEXTGEN|HIS|20240115114500||ADT^A04^ADT_A04|MSG00002|P|2.5.1|||AL|NE
EVN|A04|20240115114500
PID|1||MRN91205^^^SOUTH_CLINIC^MR||MARTINEZ^ELENA^M||19850322|F|||789 Pine Street^^Chicago^IL^60614||7735550198|||S|HIS|500987654
PV1|1|O|CLINIC^2A^05||||9012^CHEN^DAVID^W^^^MD|||||REF||||O0||||||||||||||||||||||||||20240115114500
IN1|1|UHC002|UnitedHealthcare|United Health Group|||||||20100601||||MARTINEZ^ELENA^M|SELF|19850322|789 Pine Street^^Chicago^IL^60614
EOF

# Fix permissions
chown ga:ga /home/ga/adt_a01.hl7 /home/ga/adt_a04.hl7
chmod 644 /home/ga/adt_a01.hl7 /home/ga/adt_a04.hl7

# 2. Ensure output directory exists (but is empty)
rm -rf /tmp/adt_output
mkdir -p /tmp/adt_output
chmod 777 /tmp/adt_output

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Open terminal for the agent with instructions
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "======================================================="
echo " NextGen Connect Task: Custom Metadata Columns"
echo "======================================================="
echo ""
echo "GOAL: Create a channel that extracts specific HL7 fields"
echo "      into searchable custom metadata columns."
echo ""
echo "channel Name: ADT_Metadata_Tracker"
echo "Port:         6661"
echo "Output:       /tmp/adt_output/"
echo ""
echo "REQUIRED METADATA COLUMNS:"
echo "1. PatientMRN  <- PID.3.1"
echo "2. PatientName <- PID.5"
echo "3. EventType   <- MSH.9.2"
echo ""
echo "Test Messages provided in /home/ga/:"
echo "  - adt_a01.hl7"
echo "  - adt_a04.hl7"
echo ""
echo "Sending example:"
echo "  printf \"\x0b\"; cat adt_a01.hl7; printf \"\x1c\x0d\" | nc localhost 6661"
echo ""
echo "Credentials: admin / admin"
echo "======================================================="
exec bash
' 2>/dev/null &

# 5. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="