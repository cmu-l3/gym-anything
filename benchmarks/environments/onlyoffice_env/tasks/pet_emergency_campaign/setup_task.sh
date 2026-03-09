#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Pet Emergency Campaign Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the campaign notes file (messy notes from emergency vet visit)
NOTES_PATH="$WORKSPACE_DIR/campaign_notes.txt"

cat > "$NOTES_PATH" << 'NOTESEOF'
MAXIE EMERGENCY - NOTES FROM VET

Thurs night around 9pm - heard tires screech outside
Maxie got out through fence gap we didn't know about
Witnesses said white sedan didnt stop

Emergency Animal Hospital - arrived 9:40pm
Dr. Chen - said fractured pelvis, internal bleeding suspected
They stabilized her - xrays, ultrasound, IV fluids, overnight monitoring, pain meds
ALREADY PAID: $2,800 (on credit card)

STILL NEEDED - got these estimates Friday:

Orthopedic Surgery (Dr. Morrison):
- Pelvic fracture repair with pins and plate: $3,800
- Anesthesia and monitoring: $650
- Post-surgical hospitalization (2-3 days): $900

Follow-up Care (estimate from Dr. Chen):
- Pain medication (3 weeks): $180
- Antibiotics (10 days): $85
- Follow-up x-rays and exams (2 visits): $420
- Restricted activity crate rental (6 weeks): $165

TOTAL NEEDED: ??? (need to add up)

Maxie is 7 years old, golden retriever mix, rescued her 5 years ago from shelter
She's recovering in hospital now - surgery scheduled for Monday if we can pay
My credit card is maxed from the emergency visit
Need help to save her
NOTESEOF

chown ga:ga "$NOTES_PATH"
echo "✅ Campaign notes created at: $NOTES_PATH"

# Create an empty campaign document for the agent to work in
DOC_PATH="$WORKSPACE_DIR/maxie_campaign.docx"

cat > /tmp/create_empty_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

# Create a completely blank document
doc = Document()
doc.save(sys.argv[1])
print(f"Empty document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_empty_doc.py
python3 /tmp/create_empty_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Empty campaign document created at: $DOC_PATH"

# Launch ONLYOFFICE with the empty campaign document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_campaign_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_campaign_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Pet Emergency Campaign Task Setup Complete ==="
echo ""
echo "📋 Task Overview:"
echo "  Read the notes at: $NOTES_PATH"
echo "  Create campaign document at: $DOC_PATH"
echo ""
echo "📝 Required Sections:"
echo "  1. Campaign Title (must mention Maxie and emergency/surgery)"
echo "  2. Story (2-3 paragraphs: what happened, current status, urgency)"
echo "  3. Budget Breakdown TABLE with all costs:"
echo "     - Initial emergency care: \$2,800 (paid)"
echo "     - Pelvic fracture repair: \$3,800"
echo "     - Anesthesia and monitoring: \$650"
echo "     - Post-surgical hospitalization: \$900"
echo "     - Pain medication: \$180"
echo "     - Antibiotics: \$85"
echo "     - Follow-up x-rays and exams: \$420"
echo "     - Crate rental: \$165"
echo "     TOTALS: \$2,800 paid, \$6,200 needed, \$9,000 total"
echo "  4. Thank you / closing"
echo ""
echo "💾 Save the document when complete (Ctrl+S)"