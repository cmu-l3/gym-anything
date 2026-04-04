#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Rental Scam Evidence Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
DESKTOP_DIR="/home/ga/Desktop"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$DESKTOP_DIR"

# Create the raw notes file on Desktop
NOTES_PATH="$DESKTOP_DIR/scam_notes.txt"

cat > "$NOTES_PATH" << 'EOF'
RENTAL SCAM - MY NOTES

Saw listing on Craigslist march 15 - beautiful 2BR in Mission for $2100/month
Emailed david.martinez.rentals@gmail.com march 16 morning
Got response march 16 evening - seemed professional, said he was overseas
He sent application form march 17 via email
Looked legit - had lease agreement and everything
I sent deposit march 18 via zelle $1200 plus $15 zelle fee
He said need background check - paid $270 to his "verification service" march 19
Tried calling march 20 morning - number went to voicemail
Checked craigslist listing march 20 - GONE
Got suspicious - looked up property address
Called REAL landlord march 20 afternoon - they said they never listed it and this is a known scam
I'm an idiot

SCAMMER INFO:
Name: David Martinez (probably fake)
Phone: 415-555-0147
Email for initial contact: david.martinez.rentals@gmail.com  
Email for zelle: david.m.rentals@yahoo.com
"Verification service" website: no longer loads

WHAT I NEED TO DO:
- File police report ASAP
- Submit dispute to my bank (have 10 days!)
- Report to Craigslist
- Report to Zelle/my bank
- Post on reddit to warn others
- Check if identity theft protection needed

TOTAL LOSS: $1200 + $15 + $270 = $1485
EOF

chown ga:ga "$NOTES_PATH"

echo "✅ Scam notes created at: $NOTES_PATH"

# Launch ONLYOFFICE with a blank new document
echo "Launching ONLYOFFICE Document Editor with blank document..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new-document > /tmp/onlyoffice_rental_scam_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_rental_scam_task.log || true
    # Don't exit - allow task to continue
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
    # Don't exit - allow task to continue
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct area
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

# Give editor a moment to fully initialize
sleep 2

echo "=== Rental Scam Evidence Task Setup Complete ==="
echo ""
echo "📝 Task Overview:"
echo "   You've been scammed out of \$1,485 in a rental fraud scheme."
echo "   Create a structured evidence report to submit to your bank and police."
echo ""
echo "📄 Raw notes available at: ~/Desktop/scam_notes.txt"
echo ""
echo "✅ Required Document Structure:"
echo "   1. Case Header (bold) - incident type, dates, total loss"
echo "   2. Timeline of Events (chronological) - at least 5 dated entries"
echo "   3. Evidence Inventory - list of evidence items"
echo "   4. Financial Loss Calculation - itemized breakdown totaling \$1,485"
echo "   5. Scammer Contact Information - name, phone, email"
echo "   6. Next Steps Checklist - actions to take"
echo ""
echo "💾 Save as: ~/Documents/TextDocuments/rental_scam_evidence.docx"
echo ""
echo "⏰ Bank dispute deadline: 10 days from incident"