#!/bin/bash
set -u

echo "=== Setting up lockbit_ransomware_attack_tree task ==="

# 1. Create the Threat Intelligence Report
# Content based on CISA Advisory AA23-075A (LockBit 3.0)
cat > /home/ga/Desktop/lockbit_report.txt << 'EOF'
CYBER THREAT INTELLIGENCE REPORT: LOCKBIT 3.0 (BLACK)
Reference: CISA Advisory AA23-075A
Classification: INTERNAL USE ONLY

ROOT GOAL:
LockBit Ransomware Infection (Data Encryption & Exfiltration)

ATTACK PATH ANALYSIS:

1. INITIAL ACCESS (Tactics to enter the network) - [OR Logic]
   The affiliate can gain access through ANY of these methods:
   - Phishing (T1566): Sending malicious emails with attachments/links.
   - Exploit Public-Facing Application (T1190): Exploiting vulnerabilities in web servers.
   - External Remote Services (T1133): Accessing via VPN or RDP using compromised credentials.
   - Valid Accounts (T1078): Purchased credentials from access brokers.

2. EXECUTION & PERSISTENCE (Establishing foothold) - [AND Logic]
   Once inside, the attacker performs BOTH:
   - Command and Scripting Interpreter (T1059): Using PowerShell or CMD.
   - Scheduled Task/Job (T1053): Creating tasks to maintain persistence across reboots.

3. CREDENTIAL ACCESS & LATERAL MOVEMENT (Moving through network)
   To escalate privileges and spread, they use:
   - OS Credential Dumping (T1003): Using tools like Mimikatz or LSASS dumping.
     -> LEADS TO ->
   - Remote Services (T1021): Moving laterally via RDP (Remote Desktop Protocol) or SMB.
   - SMB/Windows Admin Shares (T1021.002): Using PsExec or Cobalt Strike.

4. IMPACT (Final Objectives)
   - Data Encrypted for Impact (T1486): Using the LockBit encryptor.
   - Inhibit System Recovery (T1490): Deleting Volume Shadow Copies using vssadmin.

INSTRUCTIONS FOR ANALYST:
Create an Attack Tree diagram mapping these paths. 
- Color Code: Blue for Initial Access, Orange for Movement/Execution, Red for Impact/Goal.
- Label all nodes with the Technique Name and MITRE ID (e.g., "Phishing (T1566)").
EOF

chown ga:ga /home/ga/Desktop/lockbit_report.txt
chmod 644 /home/ga/Desktop/lockbit_report.txt

# 2. Record Task Start Time (Anti-Gaming)
date +%s > /tmp/task_start_time.txt

# 3. Clean previous artifacts
rm -f /home/ga/Desktop/lockbit_attack_tree.drawio
rm -f /home/ga/Desktop/lockbit_attack_tree.png

# 4. Launch draw.io
# Find binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then DRAWIO_BIN="drawio"; 
elif [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio"; 
elif [ -f /usr/bin/drawio ]; then DRAWIO_BIN="/usr/bin/drawio"; fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found"
    exit 1
fi

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"

# 5. Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# 6. Handle Startup Dialog (Create New / Open Existing)
# Pressing Escape usually dismisses the dialog and leaves a blank canvas or prompts to create
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
# Just in case it asks "Save changes?" or similar on escape, ensure we are on a blank canvas
# A blank canvas is the default state after dismissing the start screen in many versions.

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="