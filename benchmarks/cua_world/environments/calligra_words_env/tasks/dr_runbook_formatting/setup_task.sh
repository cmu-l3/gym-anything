#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up DR Runbook Formatting Task ==="

# 1. Clean up and set permissions
install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes
rm -f /home/ga/Documents/postgres_failover_runbook.odt
rm -f /home/ga/Desktop/runbook_standards.txt

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Create the formatting specification on the Desktop
cat > /home/ga/Desktop/runbook_standards.txt << 'EOF'
CORPORATE IT COMPLIANCE STANDARDS - TIER 1 RUNBOOKS

All Tier 1 disaster recovery runbooks must adhere strictly to the following formatting standards before publication:

1. DOCUMENT HEADER:
   Every runbook must contain a document Header (Insert -> Header) with the exact text:
   CRITICAL SYSTEM RUNBOOK - TIER 1
   This header text must be aligned to the Right.

2. TABLE OF CONTENTS:
   A Table of Contents must be inserted immediately after the "Document Control" section to allow quick navigation during an outage.

3. SAFETY WARNINGS:
   Any paragraph beginning with "WARNING:" or "CRITICAL:" must be formatted so the entire paragraph is:
   - Font Color: Red
   - Font Weight: Bold

4. TERMINAL COMMANDS:
   The draft contains markdown-style backticks (`) around terminal commands.
   - You must remove all backtick characters.
   - You must format the command text itself with a Monospace font (e.g., Courier, Liberation Mono, Hack, etc.).
   - The command text must also be Bolded.

5. EXECUTION STEPS:
   Do not use hardcoded "Step X:" text prefixes. 
   - You must delete the "Step X:" prefixes.
   - You must format the execution steps as an automated Numbered List using the word processor's list feature.
EOF

chown ga:ga /home/ga/Desktop/runbook_standards.txt

# 4. Create the unformatted DR runbook document using odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Document Control
add_paragraph("Document Control")
add_paragraph("Author: Database Reliability Engineering (DBRE) Team")
add_paragraph("Last Updated: October 2025")
add_paragraph("Approval: IT Operations Director")
add_paragraph("")

# Title & Phase 1
add_paragraph("PostgreSQL Tier 1 Failover Procedure")
add_paragraph("")
add_paragraph("Phase 1: Verification")
add_paragraph("WARNING: Do not proceed if the primary node is still actively serving read-write traffic. Split-brain will occur and cause massive data corruption.")
add_paragraph("Step 1: Check the cluster state on the standby node.")
add_paragraph("Run `repmgr cluster show` and verify the primary is marked as failed.")
add_paragraph("Step 2: Verify PostgreSQL service status.")
add_paragraph("Execute `sudo systemctl status postgresql` on both nodes to ensure the primary is completely stopped.")
add_paragraph("")

# Phase 2
add_paragraph("Phase 2: Execution")
add_paragraph("CRITICAL: Ensure the application connection poolers (PgBouncer) are paused before promotion to prevent connection drops.")
add_paragraph("Step 3: Promote the standby to primary.")
add_paragraph("Execute `repmgr standby promote` on the target standby node. Wait for the promotion log to confirm success.")
add_paragraph("")

# Phase 3
add_paragraph("Phase 3: Post-Failover Validation")
add_paragraph("Step 4: Check if the new primary is accepting connections.")
add_paragraph("Run `pg_isready` to confirm the database is up and ready for traffic.")
add_paragraph("Step 5: Resume PgBouncer traffic.")
add_paragraph("Unpause the connection poolers to allow applications to connect to the new primary.")

doc.save("/home/ga/Documents/postgres_failover_runbook.odt")
PYEOF

chown ga:ga /home/ga/Documents/postgres_failover_runbook.odt

# 5. Launch Calligra Words and open the document
launch_calligra_document "/home/ga/Documents/postgres_failover_runbook.odt"

# 6. Wait for window and maximize
if wait_for_window "Calligra Words" 30; then
    WID=$(get_calligra_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="