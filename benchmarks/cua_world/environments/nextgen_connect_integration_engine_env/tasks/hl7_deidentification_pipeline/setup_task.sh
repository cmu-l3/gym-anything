#!/bin/bash
echo "=== Setting up HL7 De-identification Pipeline Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create input and output directories
mkdir -p /home/ga/hl7_input
mkdir -p /home/ga/hl7_output

# Ensure output directory is empty and writable
rm -f /home/ga/hl7_output/*
chown -R ga:ga /home/ga/hl7_input /home/ga/hl7_output
chmod 777 /home/ga/hl7_output

# Generate Sample HL7 Messages with PHI

# Message 1: Johnson
cat > /home/ga/hl7_input/adt_msg_001.hl7 <<EOF
MSH|^~\\&|HIS|MedCenter|Mirth|Connect|202301010800||ADT^A01|MSG00001|P|2.3
EVN|A01|202301010800
PID|1||10001^^^MRN||JOHNSON^ROBERT^M||19800101|M|||456 OAK AVENUE^^METROPOLIS^NY^10001||(555)111-2222|||S|||987654321
PV1|1|I|ICU^01^01||||12345^DOC^PRIMARY|||||||||||||||||||||||||||||||||||||202301010800
EOF

# Message 2: Martinez
cat > /home/ga/hl7_input/adt_msg_002.hl7 <<EOF
MSH|^~\\&|HIS|MedCenter|Mirth|Connect|202301010930||ADT^A01|MSG00002|P|2.3
EVN|A01|202301010930
PID|1||10002^^^MRN||MARTINEZ^MARIA^L||19850515|F|||789 PINE STREET^^GOTHAM^NJ^07001||(555)333-4444|||M|||123456789
PV1|1|I|MED^02^02||||67890^DOC^ATTENDING|||||||||||||||||||||||||||||||||||||202301010930
EOF

# Message 3: Thompson
cat > /home/ga/hl7_input/adt_msg_003.hl7 <<EOF
MSH|^~\\&|HIS|MedCenter|Mirth|Connect|202301011045||ADT^A01|MSG00003|P|2.3
EVN|A01|202301011045
PID|1||10003^^^MRN||THOMPSON^JAMES^K||19901120|M|||321 MAPLE DRIVE^^SMALLVILLE^KS^66002||(555)999-8888|||S|||456789012
PV1|1|O|ER^03^05||||11111^DOC^EMERGENCY|||||||||||||||||||||||||||||||||||||202301011045
EOF

# Set permissions for input files
chown ga:ga /home/ga/hl7_input/*.hl7
chmod 644 /home/ga/hl7_input/*.hl7

# Ensure NextGen Connect is running
echo "Checking NextGen Connect status..."
wait_for_api 60

# Maximize Firefox if running, or launch it
if pgrep -f firefox > /dev/null; then
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
else
    # Launch Firefox to the landing page
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 5
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Input files created in /home/ga/hl7_input/"
echo "Output directory prepared at /home/ga/hl7_output/"