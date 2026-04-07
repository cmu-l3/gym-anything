#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up IT Incident RCA Formatting Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/INC-2026-042_PostMortem.odt
rm -f /home/ga/Desktop/rca_style_guide.txt

# Create the style guide
cat << 'EOF' > /home/ga/Desktop/rca_style_guide.txt
ENGINEERING RCA STYLE GUIDE

All engineering incident post-mortem documents must adhere to the following formatting standards:

1. Title & Meta: 
   - The main title MUST be Bold, Centered, and at least 16pt font.

2. Sections:
   - There must be exactly 6 main sections: Executive Summary, Impact, Timeline, Log Excerpts, Root Cause Analysis (Five Whys), Action Items.
   - All main sections MUST be formatted as Heading 1.

3. Narrative Text:
   - The body text in the Executive Summary and Impact sections MUST be justified alignment.

4. Tables:
   - The Timeline MUST be formatted as a 2-column table with headers: Timestamp, Event.
   - The Action Items MUST be formatted as a 3-column table with headers: Owner, Action Item, Status.

5. Code & Logs:
   - Any raw log excerpts or code snippets MUST be formatted with a Monospace font (e.g., Liberation Mono, Courier New).

6. Lists:
   - The "Five Whys" MUST be formatted as a proper numbered (ordered) list.
EOF
chown ga:ga /home/ga/Desktop/rca_style_guide.txt

# Create the unformatted ODT file
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add(text=""):
    doc.text.addElement(P(text=text))

# Title
add("INC-2026-042 Post-Mortem Report")
add("Incident: Production Database Split-Brain")
add("Date: October 14, 2026")
add("")

# Executive Summary
add("Executive Summary")
add("On October 14, 2026, the primary production PostgreSQL cluster experienced a split-brain condition following a brief network partition between the US-East and US-West data centers. This resulted in data inconsistency and a full outage of the customer-facing checkout system for 42 minutes.")
add("")

# Impact
add("Impact")
add("The checkout service was completely unavailable from 09:14 UTC to 09:56 UTC. Approximately 12,400 user transactions failed during this window. Customer support received 840 tickets related to the outage. Total estimated revenue impact is $215,000.")
add("")

# Timeline
add("Timeline")
add("Timestamp | Event")
add("09:12 UTC | Network partition occurs between us-east-1 and us-west-2")
add("09:14 UTC | PagerDuty alert triggered for high checkout latency")
add("09:16 UTC | Patroni attempts leader election in both partitions")
add("09:18 UTC | Split-brain condition established; both nodes accept writes")
add("09:25 UTC | Incident Commander declares SEV-1")
add("09:35 UTC | Network partition resolves; Patroni detects split-brain")
add("09:42 UTC | Secondary node fenced and demoted manually")
add("09:56 UTC | Checkout service restored and verified")
add("")

# Log Excerpts
add("Log Excerpts")
add("The following errors were observed in the Patroni logs on the secondary node:")
add("2026-10-14 09:16:22.451 UTC FATAL: remaining connection slots are reserved for non-replication superuser connections")
add("2026-10-14 09:18:05.112 UTC ERROR: requested WAL segment 000000010000004A000000F3 has already been removed")
add("2026-10-14 09:35:11.889 UTC FATAL: database system identifier differs between the primary and standby")
add("")

# Root Cause Analysis (Five Whys)
add("Root Cause Analysis (Five Whys)")
add("1. Why did the checkout system fail? The database cluster entered a split-brain state, causing write conflicts.")
add("2. Why did the database enter a split-brain state? A network partition isolated the data centers, and the consensus store timeout was configured too low.")
add("3. Why was the consensus store timeout too low? It was inadvertently reverted to the default 5 seconds during the last Chef deployment.")
add("4. Why did the Chef deployment revert the timeout? The infrastructure-as-code repository lacked the specific environment override for the production cluster.")
add("5. Why was the override missing? The code review process for the previous PR did not include a validation step for environment-specific overrides.")
add("")

# Action Items
add("Action Items")
add("Owner | Action Item | Status")
add("J. Smith | Update Patroni consensus timeout to 15 seconds | Completed")
add("A. Johnson | Add CI/CD linter for missing environment overrides | In Progress")
add("E. Davis | Conduct data reconciliation for split writes | Not Started")
add("R. Chen | Update runbook for manual node fencing | In Progress")
add("")

doc.save("/home/ga/Documents/INC-2026-042_PostMortem.odt")
PYEOF

chown ga:ga /home/ga/Documents/INC-2026-042_PostMortem.odt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch Calligra Words
launch_calligra_document "/home/ga/Documents/INC-2026-042_PostMortem.odt"

# Wait for window and maximize
wait_for_window "Calligra Words" 30
sleep 2
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="