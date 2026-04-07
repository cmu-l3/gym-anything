#!/bin/bash
set -e

echo "=== Setting up Academic Peer Review Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Kill any leftover soffice processes and remove lock files
killall -9 soffice.bin soffice 2>/dev/null || true
sleep 1
rm -f /home/ga/.openoffice/4/.lock 2>/dev/null || true
rm -f /tmp/.~lock.* 2>/dev/null || true

# Timestamp start
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up previous runs
rm -f /home/ga/Documents/proposal_draft.odt 2>/dev/null || true
rm -f /home/ga/Documents/proposal_reviewed.odt 2>/dev/null || true

# Create the ODT file using Python/odfpy (reliable, no GUI needed)
echo "Creating draft ODT file with Python..."
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P, H

doc = OpenDocumentText()

title = H(outlinelevel=1, text="Proposal: Genetics Study")
doc.text.addElement(title)
doc.text.addElement(P(text=""))

intro_heading = H(outlinelevel=2, text="Introduction")
doc.text.addElement(intro_heading)

p1 = P(text="The fruit fly Drosphila melanogaster has been a model organism for over a century. Its rapid life cycle makes it ideal for genetic studies. This experiment will be totally awesome and win a Nobel prize. We propose to use CRISPR-Cas9 to target the white gene.")
doc.text.addElement(p1)
doc.text.addElement(P(text=""))

meth_heading = H(outlinelevel=2, text="Methodology")
doc.text.addElement(meth_heading)

p2 = P(text="Previous studies have shown a 95% efficiency rate in gene editing using this protocol. We will replicate these conditions to observe phenotypic changes.")
doc.text.addElement(p2)

doc.save("/home/ga/Documents/proposal_draft.odt")
print("ODT file created successfully")
PYEOF

chown ga:ga /home/ga/Documents/proposal_draft.odt
echo "Draft ODT file created."

# Create instructions file for reference
cat > /home/ga/Documents/review_instructions.txt << 'EOF'
REVIEW INSTRUCTIONS
-------------------
1. Open 'proposal_draft.odt'.
2. Enable "Record Changes" (Edit > Changes > Record).
3. Correct "Drosphila" -> "Drosophila" (Italicize).
4. Delete the sentence about "Nobel prize".
5. Comment on "95% efficiency rate": "Please provide a citation for this figure."
6. Comment on Title: "Title is too vague. Be more specific."
7. Save as 'proposal_reviewed.odt'.
EOF
chown ga:ga /home/ga/Documents/review_instructions.txt

# Launch OpenOffice Writer with the document
echo "Launching OpenOffice Writer..."
rm -f /home/ga/.openoffice/4/.lock 2>/dev/null || true
rm -f /tmp/.~lock.proposal_draft.odt* 2>/dev/null || true
sudo -u ga DISPLAY=:1 /opt/openoffice4/program/soffice --nofirststartwizard --norestore --writer /home/ga/Documents/proposal_draft.odt > /dev/null 2>&1 &
SOFFICE_PID=$!

# Wait for Writer window OR handle the first-run wizard if it appears
echo "Waiting for OpenOffice Writer..."
WRITER_FOUND=false
WIZARD_HANDLED=false
for i in $(seq 1 90); do
    # Check for Writer window
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "proposal_draft\|Writer.*odt"; then
        echo "Writer window found after ${i}s"
        WRITER_FOUND=true
        break
    fi

    # Handle first-run wizard if it appears
    if [ "$WIZARD_HANDLED" = "false" ] && DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Welcome to OpenOffice"; then
        echo "First-run wizard detected, dismissing..."
        sleep 2
        # Page 1: Welcome - Tab to Next, Enter
        DISPLAY=:1 xdotool key Tab Tab Tab Tab Return 2>/dev/null || true
        sleep 2
        # Page 2: User info - Tab to Finish, Enter
        DISPLAY=:1 xdotool key Tab Tab Tab Tab Return 2>/dev/null || true
        sleep 2
        WIZARD_HANDLED=true
    fi

    # Dismiss BASIC error dialogs (press Enter)
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q "OpenOffice 4.1.16"; then
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 0.5
    fi

    # If soffice died, relaunch
    if ! kill -0 $SOFFICE_PID 2>/dev/null; then
        echo "soffice exited, relaunching..."
        rm -f /home/ga/.openoffice/4/.lock 2>/dev/null || true
        rm -f /tmp/.~lock.proposal_draft.odt* 2>/dev/null || true
        sleep 2
        sudo -u ga DISPLAY=:1 /opt/openoffice4/program/soffice --nofirststartwizard --norestore --writer /home/ga/Documents/proposal_draft.odt > /dev/null 2>&1 &
        SOFFICE_PID=$!
    fi

    sleep 1
done

# Dismiss any remaining error dialogs
for j in 1 2 3 4 5; do
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 0.3
done

# Close the Start Center if it's still open
DISPLAY=:1 wmctrl -c 'OpenOffice 4.1.16' 2>/dev/null || true
sleep 1

if [ "$WRITER_FOUND" = "false" ]; then
    echo "WARNING: Writer window not found, checking windows..."
    DISPLAY=:1 wmctrl -l 2>/dev/null || true
fi

# Maximize the Writer window
sleep 1
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'proposal_draft\|Writer\|\.odt\|\.doc' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Writer window maximized"
fi

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
