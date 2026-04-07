#!/bin/bash
set -e
echo "=== Setting up Regex Data Quality Router Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare Output Directories
mkdir -p /home/ga/valid
mkdir -p /home/ga/quarantine
# Ensure they are empty and writable
rm -f /home/ga/valid/*
rm -f /home/ga/quarantine/*
chown -R ga:ga /home/ga/valid /home/ga/quarantine
chmod -R 777 /home/ga/valid /home/ga/quarantine

# 2. Generate Test Data
mkdir -p /home/ga/test_messages

# Valid Message (ID: 123456)
cat > /home/ga/test_messages/valid_123456.hl7 <<EOF
MSH|^~\\&|HIS|MedCenter|LIS|Lab|202403151000||ADT^A01|MSG00001|P|2.3
EVN|A01|202403151000
PID|1||123456^^^MRN||DOE^JOHN||19800101|M
PV1|1|O
EOF

# Invalid Message (ID: ABC)
cat > /home/ga/test_messages/invalid_ABC.hl7 <<EOF
MSH|^~\\&|HIS|MedCenter|LIS|Lab|202403151005||ADT^A01|MSG00002|P|2.3
EVN|A01|202403151005
PID|1||ABC^^^MRN||SMITH^JANE||19900202|F
PV1|1|O
EOF

chown -R ga:ga /home/ga/test_messages

# 3. Create a helper script for the agent to send test messages easily
cat > /home/ga/send_tests.sh <<'EOF'
#!/bin/bash
echo "Sending Valid Message (123456)..."
# Wrap in MLLP (0x0b ... 0x1c 0x0d)
printf '\x0b' | nc -q 0 localhost 6661 2>/dev/null
cat /home/ga/test_messages/valid_123456.hl7 | nc -q 0 localhost 6661 2>/dev/null
printf '\x1c\x0d' | nc -q 0 localhost 6661 2>/dev/null
echo "Sent."
sleep 1
echo "Sending Invalid Message (ABC)..."
printf '\x0b' | nc -q 0 localhost 6661 2>/dev/null
cat /home/ga/test_messages/invalid_ABC.hl7 | nc -q 0 localhost 6661 2>/dev/null
printf '\x1c\x0d' | nc -q 0 localhost 6661 2>/dev/null
echo "Sent."
EOF
chmod +x /home/ga/send_tests.sh
chown ga:ga /home/ga/send_tests.sh

# 4. Open Terminal with Instructions
DISPLAY=:1 gnome-terminal --geometry=100x30+100+100 -- bash -c '
echo "======================================================="
echo " TASK: Regex-Based Data Quality Router"
echo "======================================================="
echo "Goal: Create a channel \"MRN_Quality_Firewall\" on port 6661."
echo ""
echo "Logic:"
echo "1. If PID-3.1 is exactly 6 digits (e.g., 123456):"
echo "   - Route to: /home/ga/valid"
echo "   - Transform: Prefix ID with \"MRN-\" (e.g., MRN-123456)"
echo ""
echo "2. If PID-3.1 is NOT 6 digits:"
echo "   - Route to: /home/ga/quarantine"
echo "   - Transform: Output text \"Invalid MRN detected: <ID>\""
echo ""
echo "Resources:"
echo " - Test messages: /home/ga/test_messages/"
echo " - Helper script: ./send_tests.sh"
echo " - Output dirs: /home/ga/valid, /home/ga/quarantine"
echo "======================================================="
exec bash
' 2>/dev/null &

# 5. Ensure Firefox is open to Landing Page
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8080 &"
fi

# Wait and maximize
sleep 5
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# 6. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="