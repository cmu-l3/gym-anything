#!/bin/bash
# Export script for "disable_auto_device_addition"
# Performs behavioral testing: Injects a log from a new IP and checks if it gets added.

echo "=== Exporting Task Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

TEST_IP="192.168.254.254"
RESULT_JSON="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Starting Behavioral Verification..."

# 1. Setup temporary IP alias to spoof the source
echo "Adding temporary IP $TEST_IP to loopback..."
sudo ip addr add "$TEST_IP/32" dev lo 2>/dev/null || true

# 2. Inject Syslog Packet using Python
# We explicitly bind to the TEST_IP so ELA sees the packet coming from there
echo "Injecting syslog packet from $TEST_IP..."
python3 -c "
import socket
import sys

try:
    msg = '<14>Oct 11 10:00:00 TestDevice sshd[9999]: Failed password for invalid user root from 1.2.3.4 port 1234 ssh2'.encode('utf-8')
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    # Bind to the alias IP to spoof source
    sock.bind(('$TEST_IP', 0))
    sock.sendto(msg, ('127.0.0.1', 514))
    print('Packet sent successfully')
except Exception as e:
    print(f'Error sending packet: {e}')
    sys.exit(1)
"

# 3. Wait for ELA to process the log
# Auto-addition usually happens within 15-30 seconds of receiving the first log
echo "Waiting 45s for ELA to process potential new device..."
sleep 45

# 4. Remove temporary IP
sudo ip addr del "$TEST_IP/32" dev lo 2>/dev/null || true

# 5. Check Database for the device
# We query the Resources table (standard ELA device table)
echo "Checking database for device $TEST_IP..."
# Note: ELA DB schema often uses 'Resources' table for devices
DB_Result=$(ela_db_query "SELECT COUNT(*) FROM Resources WHERE RESOURCE_NAME LIKE '%$TEST_IP%' OR HOST_NAME LIKE '%$TEST_IP%'")
DB_COUNT=$(echo "$DB_Result" | grep -o "[0-9]*" | head -1 || echo "0")

echo "Database count for $TEST_IP: $DB_COUNT"

# If count > 0, the device was added -> FAIL (Agent didn't disable auto-add)
# If count == 0, the device was ignored -> PASS (Agent successfully disabled auto-add)
if [ "$DB_COUNT" -eq "0" ]; then
    BEHAVIOR_CHECK_PASSED="true"
    echo "SUCCESS: Device was NOT added."
else
    BEHAVIOR_CHECK_PASSED="false"
    echo "FAILURE: Device WAS added."
fi

# 6. Capture final screenshot
take_screenshot /tmp/task_final.png

# 7. Create Result JSON
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "test_ip": "$TEST_IP",
    "device_found_in_db": $([ "$DB_COUNT" -gt 0 ] && echo "true" || echo "false"),
    "behavioral_check_passed": $BEHAVIOR_CHECK_PASSED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "=== Export Complete ==="
cat "$RESULT_JSON"