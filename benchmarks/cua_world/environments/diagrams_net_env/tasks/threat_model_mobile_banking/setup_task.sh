#!/bin/bash
set -e

echo "=== Setting up Threat Model Mobile Banking Task ==="

# 1. Ensure directories exist
mkdir -p /home/ga/Diagrams /home/ga/Desktop
chown ga:ga /home/ga/Diagrams /home/ga/Desktop

# 2. Create the Architecture Specification Document
cat > /home/ga/Desktop/mobile_banking_architecture.txt << 'EOF'
MOBILE BANKING APPLICATION - ARCHITECTURE SPECIFICATION
For Threat Modeling Review (STRIDE Methodology)
================================================================

SYSTEM OVERVIEW:
FinSecure Mobile Banking allows customers to check balances, transfer
funds, pay bills, and receive notifications via iOS/Android apps.
Admin staff manage accounts through an internal web portal.

================================================================
EXTERNAL ENTITIES (draw as rectangles with sharp corners):
================================================================
1. Mobile User - End customer using iOS/Android banking app
2. Admin User - Internal staff using web admin portal
3. Payment Processor (Stripe) - Third-party payment gateway for external transfers
4. Credit Bureau (Experian) - External credit check API for loan applications

================================================================
PROCESSES (draw as rounded rectangles or circles):
================================================================
1. API Gateway - Entry point; rate limiting, request routing, TLS termination
2. Authentication Service - Handles login, MFA, session management, OAuth2 tokens
3. Account Management Service - Balance queries, account settings, profile updates
4. Transaction Processing Engine - Fund transfers, bill payments, transaction validation
5. Notification Service - Push notifications, SMS alerts, email confirmations
6. Fraud Detection Engine - Real-time risk scoring, anomaly detection, velocity checks

================================================================
DATA STORES (draw as open-ended rectangles / parallel lines):
================================================================
1. User Credentials DB (PostgreSQL) - Usernames, hashed passwords, MFA secrets
2. Account Balance DB (PostgreSQL) - Account numbers, balances, account metadata
3. Transaction Log DB (PostgreSQL) - All transaction records with timestamps
4. Audit Log (Elasticsearch) - Security events, access logs, admin actions
5. Session Cache (Redis) - Active session tokens, rate limit counters

================================================================
TRUST BOUNDARIES (draw as dashed-line rectangles grouping components):
================================================================
TB-1: "Mobile Device" - Contains: Mobile User (untrusted zone)
TB-2: "DMZ / Perimeter Network" - Contains: API Gateway
TB-3: "Internal Services Network" - Contains: Authentication Service,
       Account Management Service, Transaction Processing Engine,
       Notification Service, Fraud Detection Engine, AND all 5 Data Stores
TB-4: "External Third-Party Services" - Contains: Payment Processor, Credit Bureau

================================================================
DATA FLOWS (draw as labeled arrows between components):
================================================================
DF-01: Mobile User -> API Gateway: "Login Credentials (username + password + MFA code)"
DF-02: Mobile User -> API Gateway: "Transaction Request (recipient, amount, currency)"
DF-03: API Gateway -> Authentication Service: "Auth Request (credentials + device fingerprint)"
DF-04: Authentication Service -> User Credentials DB: "Credential Verification Query"
DF-05: Authentication Service -> Session Cache: "Store/Validate Session Token"
DF-06: Authentication Service -> API Gateway: "Auth Token (JWT)"
DF-07: API Gateway -> Account Management Service: "Balance Query (account_id + token)"
DF-08: Account Management Service -> Account Balance DB: "Read/Write Account Balance"
DF-09: API Gateway -> Transaction Processing Engine: "Transfer Request (validated)"
DF-10: Transaction Processing Engine -> Account Balance DB: "Debit/Credit Operations"
DF-11: Transaction Processing Engine -> Transaction Log DB: "Record Transaction"
DF-12: Transaction Processing Engine -> Payment Processor: "External Transfer (amount, routing)"
DF-13: Transaction Processing Engine -> Fraud Detection Engine: "Risk Score Request"
DF-14: Fraud Detection Engine -> Transaction Log DB: "Historical Pattern Query"
DF-15: Notification Service -> Mobile User: "Push Notification / SMS Alert"
DF-16: Admin User -> API Gateway: "Admin Commands (account freeze, audit query)"
DF-17: All Services -> Audit Log: "Security Event Logging"
DF-18: Account Management Service -> Credit Bureau: "Credit Check Request"

================================================================
STRIDE THREAT ANNOTATIONS (add as colored notes/callouts on these flows):
================================================================
THREAT-1 on DF-01: SPOOFING - "Credential stuffing attack using breached 
    password databases. Attacker impersonates legitimate user." [HIGH]

THREAT-2 on DF-06: TAMPERING - "JWT token manipulation to escalate 
    privileges or extend session lifetime." [HIGH]

THREAT-3 on DF-11: REPUDIATION - "User disputes transaction. Insufficient
    logging may prevent proving transaction was authorized." [MEDIUM]

THREAT-4 on DF-04: INFORMATION DISCLOSURE - "SQL injection on credential
    query could expose password hashes of all users." [CRITICAL]

THREAT-5 on DF-09: DENIAL OF SERVICE - "Flood of transfer requests 
    overwhelming transaction engine; no per-user rate limit." [MEDIUM]

THREAT-6 on DF-16: ELEVATION OF PRIVILEGE - "Compromised admin credentials
    grant unrestricted access to freeze/unfreeze any account." [CRITICAL]

================================================================
PAGE 2 REQUIREMENTS - THREAT SUMMARY TABLE:
================================================================
Create a second page named "Threat Summary" with a table containing:
- Threat ID (THREAT-1 through THREAT-6)
- STRIDE Category (Spoofing/Tampering/Repudiation/Info Disclosure/DoS/EoP)
- Affected Data Flow (DF-XX identifier)
- Affected Components (source -> target)
- Description (brief)
- Severity (CRITICAL/HIGH/MEDIUM)
EOF
chown ga:ga /home/ga/Desktop/mobile_banking_architecture.txt
chmod 644 /home/ga/Desktop/mobile_banking_architecture.txt

# 3. Create the starter diagram file (Minimal XML)
cat > /home/ga/Diagrams/threat_model.drawio << 'EOF'
<mxfile host="Electron" modified="2024-03-01T10:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/21.6.8 Chrome/114.0.5735.289 Electron/25.5.0 Safari/537.36" etag="minimal_starter" version="21.6.8" type="device">
  <diagram id="PrTyb65d-20s9-A4n7" name="Threat Model">
    <mxGraphModel dx="1422" dy="808" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="title_text" value="Mobile Banking Threat Model" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=24;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="280" y="40" width="360" height="40" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF
chown ga:ga /home/ga/Diagrams/threat_model.drawio
chmod 644 /home/ga/Diagrams/threat_model.drawio

# 4. Remove any previous outputs
rm -f /home/ga/Diagrams/threat_model.pdf 2>/dev/null || true

# 5. Record initial state for verification
date +%s > /tmp/task_start_time.txt
stat -c %s /home/ga/Diagrams/threat_model.drawio > /tmp/initial_file_size.txt
echo "1" > /tmp/initial_page_count.txt # Starter has 1 page

# 6. Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/threat_model.drawio > /tmp/drawio.log 2>&1 &"

# 7. Wait for window and dismiss update dialog aggressively
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Dismiss update dialog (Escape, Tab+Enter, Click)
sleep 5
echo "Attempting to dismiss update dialog..."
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done
# Try clicking typical 'Cancel' button area just in case
DISPLAY=:1 xdotool mousemove 960 580 click 1 2>/dev/null || true

# 8. Open the text file as well so the agent sees it
echo "Opening requirements document..."
su - ga -c "DISPLAY=:1 xdg-open /home/ga/Desktop/mobile_banking_architecture.txt &"

# 9. Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="