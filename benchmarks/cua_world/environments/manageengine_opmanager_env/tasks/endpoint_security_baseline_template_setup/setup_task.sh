#!/bin/bash
# setup_task.sh — Endpoint Security Baseline Template Setup
# Waits for OpManager to be ready, writes the security mandate document to the desktop,
# and opens Firefox.

source /workspace/scripts/task_utils.sh

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=120
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] ERROR: OpManager not ready after ${WAIT_TIMEOUT}s" >&2
        exit 1
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# Write the security mandate document to the desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/security_baseline_mandate.txt" << 'MANDATE_EOF'
SECURITY MONITORING MANDATE
Document ID: SEC-MANDATE-0091
Version: 1.0
Effective Date: 2024-05-15
Owner: Information Security Operations

1. BACKGROUND
All secure Windows server infrastructure must run our standard suite of endpoint 
agents for EDR, log forwarding, and vulnerability scanning. The Network Operations 
Center must ensure these agents are actively monitored for uptime via Windows 
Service monitoring.

2. REQUIRED WINDOWS SERVICES
You must add the following services to the global OpManager Windows Services catalog
(Settings > Monitoring > Windows Services):

  A. CrowdStrike EDR
     - Service Name: csagent
     - Display Name: CrowdStrike-Falcon-Sensor
  
  B. Qualys Vulnerability Scanner
     - Service Name: QualysAgent
     - Display Name: Qualys-Cloud-Agent
  
  C. Splunk Log Forwarder
     - Service Name: SplunkForwarder
     - Display Name: Splunk-Universal-Forwarder

3. REQUIRED DEVICE TEMPLATE
To ensure these monitors are automatically applied to new servers, create a new 
Device Template in OpManager (Settings > Configuration > Device Templates):

  - Template Name: Windows-Server-Secure-Baseline
  - Vendor: Microsoft (or Windows)
  - Category: Server
  - System OID: .1.3.6.1.4.1.311.1.1.3.1.3

Once the template is created, associate the three Windows Services defined in 
Step 2 with this template.

END OF MANDATE
MANDATE_EOF

chown ga:ga "$DESKTOP_DIR/security_baseline_mandate.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Security mandate written to $DESKTOP_DIR/security_baseline_mandate.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/endpoint_security_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/endpoint_security_setup_screenshot.png" || true

echo "[setup] endpoint_security_baseline_template_setup complete."