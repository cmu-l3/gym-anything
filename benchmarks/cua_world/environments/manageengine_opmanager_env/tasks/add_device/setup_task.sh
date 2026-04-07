#!/bin/bash
echo "=== Setting up Add Device Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify OpManager is running (with extended timeout for slow starts)
echo "Checking OpManager health..."
if ! wait_for_opmanager_ready 120; then
    echo "WARNING: OpManager may not be fully ready"
fi

# Verify SNMP agent is running on the VM (provides real monitoring data)
echo "Verifying SNMP agent status..."
systemctl status snmpd --no-pager 2>/dev/null | head -5 || true
echo "SNMP test (real system data):"
snmpwalk -v2c -c public 127.0.0.1 sysDescr 2>/dev/null || echo "SNMP check deferred"

# Get the VM's actual IP address for the task
VM_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)10\.\d+\.\d+\.\d+' | head -1 || echo "10.0.2.15")
echo "VM IP address: $VM_IP"
echo "$VM_IP" > /tmp/task_vm_ip

# Record initial device count for verification
echo "Recording initial state..."
INITIAL_DEVICE_LIST=$(opmanager_api_get "/api/json/device/listDevices" 2>/dev/null)
echo "$INITIAL_DEVICE_LIST" > /tmp/initial_device_list.json
echo "Initial device list: $(echo "$INITIAL_DEVICE_LIST" | head -c 200)"

# Record timestamp
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso

# Ensure Firefox is running and showing OpManager (with retry/recovery)
echo "Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Add Device Task Setup Complete ==="
echo ""
echo "Task: Add a new device to OpManager"
echo "  IP Address: $VM_IP (or 10.0.2.15)"
echo "  Display Name: Linux-Server-01"
echo "  Type: Server"
echo "  SNMP Community: public"
echo ""
echo "OpManager Login: admin / Admin@123"
echo "OpManager URL: $OPMANAGER_URL"
echo ""
