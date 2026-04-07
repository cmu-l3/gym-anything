#!/bin/bash
echo "=== Setting up Content Based Routing Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Clean up any previous output directories to ensure a clean state
rm -rf /tmp/output/adt /tmp/output/orm /tmp/output/oru 2>/dev/null || true

# Generate Sample HL7 Messages for the agent to use
# ADT^A01
cat > /home/ga/sample_adt.hl7 <<EOF
MSH|^~\\&|ADT_SYS|MEMORIAL|HIS|MEMORIAL|20240115120000||ADT^A01|MSG001|P|2.3
EVN|A01|20240115120000
PID|1||12345^^^MH||DOE^JOHN||19800101|M
PV1|1|I|ICU^^^MH
EOF

# ORM^O01
cat > /home/ga/sample_orm.hl7 <<EOF
MSH|^~\\&|ORDER_SYS|MEMORIAL|LAB|MEMORIAL|20240115120500||ORM^O01|MSG002|P|2.3
PID|1||12345^^^MH||DOE^JOHN||19800101|M
ORC|NW|ORD001
OBR|1|ORD001||CBC
EOF

# ORU^R01
cat > /home/ga/sample_oru.hl7 <<EOF
MSH|^~\\&|LAB_SYS|MEMORIAL|HIS|MEMORIAL|20240115121000||ORU^R01|MSG003|P|2.3
PID|1||12345^^^MH||DOE^JOHN||19800101|M
OBR|1|ORD001||CBC
OBX|1|NM|WBC||7.5|10*3/uL
EOF

chown ga:ga /home/ga/*.hl7
chmod 644 /home/ga/*.hl7

# Wait for API to be ready
wait_for_api 60

# Open a terminal with instructions
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "======================================================="
echo " NextGen Connect - Content Based Routing Task"
echo "======================================================="
echo ""
echo "GOAL: Configure channel \"HL7_Message_Router\""
echo ""
echo "SPECIFICATIONS:"
echo "  1. Source: TCP Listener @ Port 6661"
echo "  2. Destinations (File Writers):"
echo "     - \"ADT_Destination\" -> /tmp/output/adt/ (Filter: MSH-9.1=ADT)"
echo "     - \"ORM_Destination\" -> /tmp/output/orm/ (Filter: MSH-9.1=ORM)"
echo "     - \"ORU_Destination\" -> /tmp/output/oru/ (Filter: MSH-9.1=ORU)"
echo ""
echo "SAMPLE DATA:"
echo "  - /home/ga/sample_adt.hl7"
echo "  - /home/ga/sample_orm.hl7"
echo "  - /home/ga/sample_oru.hl7"
echo ""
echo "TOOLS:"
echo "  - REST API: https://localhost:8443/api (admin/admin)"
echo "  - Web Dashboard: https://localhost:8443"
echo "  - Send HL7: printf \"\x0b...\x1c\x0d\" | nc localhost 6661"
echo ""
echo "======================================================="
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="