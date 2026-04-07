#!/bin/bash
set -e

echo "=== Setting up Cybersecurity IR Playbook Formatting task ==="

# Source ONLYOFFICE task utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state
cleanup_temp_files
kill_onlyoffice ga
sleep 1

# Setup directories
TEXT_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$TEXT_DIR"

INPUT_FILE="$TEXT_DIR/ransomware_playbook_raw.txt"
OUTPUT_FILE="$TEXT_DIR/ir_playbook_formatted.docx"

# Remove any existing output files
rm -f "$OUTPUT_FILE" 2>/dev/null || true

# Generate the raw unstructured text draft
cat > "$INPUT_FILE" << 'EOF'
Ransomware Incident Response Playbook

Last Updated: October 2024

CONFIDENTIAL: Internal Security Operations Center (SOC) Use Only

Phase 1: Preparation
Maintain updated offline backups. Ensure endpoint detection and response (EDR) agents are deployed to all workstations and servers.

Phase 2: Detection & Analysis
Identify the ransomware variant and the initial infection vector. Monitor for unusual lateral movement or bulk file encryption events.

Phase 3: Containment, Eradication, & Recovery
Isolate infected hosts from the network immediately. Do not power them down. Restore encrypted files from the latest clean offline backup.

Phase 4: Post-Incident Activity
Conduct a post-mortem review. Update IoCs and firewall rules. Determine if data exfiltration occurred and initiate regulatory notifications if necessary.

Severity Classification
Severity Level | Description | Target Response Time
Low | Isolated malware, easily contained | 24 Hours
Medium | Ransomware affecting single department | 4 Hours
High | Active ransomware spreading laterally | 1 Hour
Critical | Enterprise-wide encryption event | Immediate
EOF

chown ga:ga "$INPUT_FILE"

# Launch ONLYOFFICE Document Editor with the raw file
echo "Launching ONLYOFFICE..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$INPUT_FILE' > /tmp/onlyoffice_launch.log 2>&1 &"

# Wait for the application window to appear
wait_for_window "ONLYOFFICE\|Desktop Editors" 30

# Focus and maximize ONLYOFFICE window
focus_onlyoffice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
focus_onlyoffice_window

# Take initial screenshot of the starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="