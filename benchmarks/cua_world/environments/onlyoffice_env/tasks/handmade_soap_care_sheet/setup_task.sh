#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Handmade Soap Care Sheet Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy notes file
NOTES_PATH="$WORKSPACE_DIR/soap_care_notes.txt"

cat > "$NOTES_PATH" << 'NOTESEOF'
SOAP CARE NOTES

customer asked why bar got mushy - told them keep it dry between uses

safety: avoid eyes, discontinue if irritation, external use only

how long does it last? depends on usage but usually 4-6 weeks for daily shower use

storage: keep in draining soap dish, don't leave in water puddle, keep dry between uses, don't store in sealed container

customer said bar is too soft - explained our soaps are glycerin-rich and naturally softer, this is normal

problem: white film on bar - told them this is soda ash, totally harmless, just cosmetic, rinse off

why different colors? natural colorants, may fade over time, doesn't affect quality

can I use on face? yes but avoid eye area, patch test first if sensitive skin

problem: bar cracked in half - explained this can happen with natural soaps, just use both pieces

how to make it last longer: use a washcloth or loofah instead of rubbing directly, keep dry, cut bar in half

expiration? best within 12 months, won't go bad but scent fades

allergies? check ingredient list, common allergens are coconut oil and shea butter, patch test

why does scent fade? essential oils are natural, they evaporate, especially if soap sits in steamy bathroom

customer complained about soap dissolving too fast - reminded them to use soap dish with drainage

safety reminder: if skin irritation occurs stop using immediately, for external use only

storage tip: if you buy multiple bars, store extras in cool dry place, not bathroom

problem: soap feels slimy - this is normal for glycerin soaps, it's the moisturizing glycerin not dirt

can kids use it? yes but supervise young children, avoid contact with eyes

problem: bar has spots or discoloration - natural ingredients can cause variations, safe to use

eco tip: use every last bit - press small pieces onto new bar or save scraps for soap bag
NOTESEOF

chown ga:ga "$NOTES_PATH"
echo "✅ Notes file created at: $NOTES_PATH"

# Create a starter document with just a title to get them going
DOC_PATH="$WORKSPACE_DIR/Soap_Care_Instructions.docx"

cat > /tmp/create_starter_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt
import sys

doc = Document()

# Add a placeholder title to indicate where to start
para = doc.add_paragraph("Natural Soap Care & FAQ")
para.style = 'Title'

# Add a hint paragraph
hint = doc.add_paragraph()
hint.add_run("Instructions: Organize the notes from soap_care_notes.txt into clear sections with headings, bullet points, and bold safety warnings.").italic = True

doc.add_paragraph()  # Empty space for them to work

doc.save(sys.argv[1])
print(f"Starter document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_starter_doc.py
python3 /tmp/create_starter_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Starter document created at: $DOC_PATH"

# Launch ONLYOFFICE with the starter document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_soap_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_soap_task.log || true
    # Don't exit - let the task continue in case it starts later
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
    # Don't exit - let the task continue
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Handmade Soap Care Sheet Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "You make handmade natural soaps and need a professional care instruction sheet."
echo "You have messy notes from customer interactions that need to be organized."
echo ""
echo "📝 YOUR TASK:"
echo "1. Read the notes from: $NOTES_PATH"
echo "2. Organize them into a professional document with these sections:"
echo "   - Storage & Handling"
echo "   - Safety Information"
echo "   - Frequently Asked Questions"
echo "   - Troubleshooting Common Issues"
echo ""
echo "3. Format for readability:"
echo "   - Use heading styles for section titles"
echo "   - Use bullet points (not paragraphs)"
echo "   - Make safety warnings BOLD (especially 'avoid eyes' and 'discontinue if irritation')"
echo "   - Professional appearance (no all-caps, proper spacing)"
echo ""
echo "4. Save the document: $DOC_PATH"
echo ""
echo "💡 TIP: You can open the notes file in a text editor or view it to reference while editing."