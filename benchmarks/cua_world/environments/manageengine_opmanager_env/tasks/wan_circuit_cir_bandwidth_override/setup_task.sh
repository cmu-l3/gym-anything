#!/bin/bash
# setup_task.sh — WAN Circuit CIR Bandwidth Override
echo "=== Setting up WAN Circuit CIR Bandwidth Override Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/wan_task_start.txt

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] WARNING: OpManager not ready after ${WAIT_TIMEOUT}s" >&2
        break
    fi
done
echo "[setup] OpManager is ready."

echo "[setup] Creating dummy network interfaces to simulate WAN circuits..."
modprobe dummy 2>/dev/null || true
ip link add wan-circ-01 type dummy 2>/dev/null || true
ip link set wan-circ-01 up 2>/dev/null || true
ip link add wan-circ-02 type dummy 2>/dev/null || true
ip link set wan-circ-02 up 2>/dev/null || true

# Restart SNMP daemon so it discovers the new interfaces
systemctl restart snmpd 2>/dev/null || true
sleep 5

# Write the task instruction ticket to the desktop
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/circuit_upgrade_ticket.txt" << 'EOF'
TICKET: INC-848202
SUBJECT: WAN Circuit CIR Upgrade

Our two SD-WAN internet circuits have been logically upgraded by the ISP. 
The physical handoffs remain 10 Gbps, but the contracted bandwidth (CIR) has been increased to 2.5 Gbps (2500 Mbps).

Please update the monitoring system for the local gateway (127.0.0.1):
1. Ensure the device 127.0.0.1 is added to OpManager and SNMP interfaces are discovered.
2. Locate the two new WAN interfaces: 'wan-circ-01' and 'wan-circ-02'.
3. Override their physical port speeds (In Speed and Out Speed) to exactly 2500 Mbps (2.5 Gbps).
4. Apply strict bandwidth utilization alerts for both interfaces:
   - Rx Traffic (Inbound) Warning: 85%
   - Rx Traffic (Inbound) Critical: 95%
   - Tx Traffic (Outbound) Warning: 85%
   - Tx Traffic (Outbound) Critical: 95%

Thank you,
Network Engineering Team
EOF

chown -R ga:ga "$DESKTOP_DIR" 2>/dev/null || true

# Ensure Firefox is open on the OpManager dashboard and maximized
ensure_firefox_on_opmanager || true

# Take initial screenshot for verification evidence
echo "Capturing initial state..."
sleep 2
take_screenshot "/tmp/task_initial.png" || true

echo "=== Task setup complete ==="