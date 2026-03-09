#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero harmlessly

echo "=== Setting up stride_threat_model_dfd task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any previous outputs
rm -f /home/ga/Desktop/payment_threat_model.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/payment_threat_model.png 2>/dev/null || true

# Create the System Specification File
cat > /home/ga/Desktop/payment_system_spec.txt << 'SPECEOF'
PAYMENT PROCESSING SYSTEM SPECIFICATION
=======================================

ARCHITECTURE OVERVIEW
The system processes credit card payments from web and mobile clients. It adheres to PCI-DSS network segmentation requirements.

TRUST BOUNDARIES & ZONES
1. Internet / Untrusted Zone
   - Contains: Customer Browser, Mobile App
   
2. DMZ (Demilitarized Zone) - Public facing
   - Contains: Web Server (serves UI), API Gateway (ingress point)
   
3. Internal Network (High Trust)
   - Contains: 
     * Authentication Service (validates tokens)
     * Payment Processor (core logic)
     * Fraud Detection Engine (risk scoring)
     * Notification Service (emails/SMS)
     * User Database (PostgreSQL)
     * Transaction Database (PostgreSQL)
     * Audit Log (Immutable storage)

4. External Partner Network
   - Contains: Payment Gateway (Stripe/Adyen), Bank Network

DATA FLOWS
1. Customer Browser -> Web Server [HTTPS credentials]
2. Mobile App -> API Gateway [OAuth token + Payment Request]
3. Web Server -> API Gateway [Forwarded Request]
4. API Gateway -> Authentication Service [Token Validation]
5. Authentication Service -> API Gateway [Auth Response]
6. API Gateway -> Payment Processor [Validated Payment Request]
7. Payment Processor -> Fraud Detection Engine [Tx Details]
8. Fraud Detection Engine -> Payment Processor [Risk Score]
9. Payment Processor -> Payment Gateway (Stripe) [Tokenized Charge]
10. Payment Gateway -> Bank Network [Settlement Request]
11. Bank Network -> Payment Gateway [Response]
12. Payment Processor -> Transaction Database [Record Tx]
13. Authentication Service -> User Database [Lookup User]
14. Payment Processor -> Audit Log [Log Event]
15. Payment Processor -> Notification Service [Trigger Alert]
16. Notification Service -> Customer Browser/Mobile App [Confirmation]

THREAT MODELING REQUIREMENTS
- Create a Data Flow Diagram (DFD) modeling all the above components and flows.
- Identify at least one threat per STRIDE category (Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege).
SPECEOF

chown ga:ga /home/ga/Desktop/payment_system_spec.txt
echo "Specification created at /home/ga/Desktop/payment_system_spec.txt"

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_task.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="