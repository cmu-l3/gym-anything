#!/bin/bash
set -e

echo "=== Setting up Academic Peer Review Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Timestamp start
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up previous runs
rm -f /home/ga/Documents/proposal_draft.odt 2>/dev/null || true
rm -f /home/ga/Documents/proposal_reviewed.odt 2>/dev/null || true

# Create the source text content
cat > /tmp/proposal_source.txt << 'EOF'
Proposal: Genetics Study

Introduction
The fruit fly Drosphila melanogaster has been a model organism for over a century. Its rapid life cycle makes it ideal for genetic studies. This experiment will be totally awesome and win a Nobel prize. We propose to use CRISPR-Cas9 to target the white gene.

Methodology
Previous studies have shown a 95% efficiency rate in gene editing using this protocol. We will replicate these conditions to observe phenotypic changes.
EOF

# Convert text to ODT using OpenOffice headless mode
# This ensures we have a valid ODT file structure to start with
echo "Creating draft ODT file..."
if [ -x "/opt/openoffice4/program/soffice" ]; then
    sudo -u ga /opt/openoffice4/program/soffice --headless --convert-to odt --outdir /home/ga/Documents /tmp/proposal_source.txt
else
    # Fallback to standard command if path differs
    sudo -u ga soffice --headless --convert-to odt --outdir /home/ga/Documents /tmp/proposal_source.txt
fi

# Rename to correct filename
if [ -f "/home/ga/Documents/proposal_source.odt" ]; then
    mv /home/ga/Documents/proposal_source.odt /home/ga/Documents/proposal_draft.odt
    chown ga:ga /home/ga/Documents/proposal_draft.odt
else
    echo "ERROR: Failed to create initial ODT file"
    exit 1
fi

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
sudo -u ga DISPLAY=:1 /opt/openoffice4/program/soffice --writer /home/ga/Documents/proposal_draft.odt > /dev/null 2>&1 &

# Wait for window to appear
wait_for_window "OpenOffice Writer" 30

# Maximize the window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="