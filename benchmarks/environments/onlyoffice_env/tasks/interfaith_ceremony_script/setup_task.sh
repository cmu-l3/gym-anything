#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Interfaith Ceremony Script Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial ceremony draft document
DOC_PATH="$WORKSPACE_DIR/ceremony_draft.docx"

cat > /tmp/create_ceremony_draft.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
import sys

doc = Document()

# Add title
title = doc.add_paragraph("WEDDING CEREMONY SCRIPT")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
title_run = title.runs[0]
title_run.font.size = Pt(18)
title_run.font.bold = True

# Add couple names
couple = doc.add_paragraph("Maya Goldman & James O'Connor")
couple.alignment = WD_ALIGN_PARAGRAPH.CENTER
couple_run = couple.runs[0]
couple_run.font.size = Pt(14)

doc.add_paragraph("")
doc.add_paragraph("Saturday, June 14, 2025 - 4:00 PM")

doc.add_paragraph("")
doc.add_paragraph("="*50)
doc.add_paragraph("")

# PROCESSIONAL - incomplete
p = doc.add_paragraph("PROCESSIONAL")
p.runs[0].font.size = Pt(14)
doc.add_paragraph("[Music: what song??]")
doc.add_paragraph("Wedding party enters, followed by bride")
doc.add_paragraph("")

# WELCOME - has content but needs formatting
doc.add_paragraph("Welcome and Opening Remarks")
doc.add_paragraph("Officiant: \"Welcome, everyone. We are gathered here today to witness and celebrate the union of Maya and James. This is a joyous occasion that brings together two families, two traditions, and two hearts.\"")
doc.add_paragraph("")

# HEBREW BLESSING - placeholder
doc.add_paragraph("Jewish Blessing")
doc.add_paragraph("[FILL IN: Sheva Brachot - need the 7th blessing or something? Add transliteration for Grandma Rose]")
doc.add_paragraph("")

# READINGS - placeholder
doc.add_paragraph("Reading #1")
doc.add_paragraph("[CHOOSE READING - maybe Rumi on love? Or 1 Corinthians?]")
doc.add_paragraph("Reader: TBD")
doc.add_paragraph("")

doc.add_paragraph("Reading #2")
doc.add_paragraph("[FILL IN: Second reading - something about partnership]")
doc.add_paragraph("")

# VOWS - incomplete
doc.add_paragraph("Exchange of Vows")
doc.add_paragraph("[write custom vows here - Maya goes first]")
doc.add_paragraph("Maya: [INSERT VOWS]")
doc.add_paragraph("James: [INSERT VOWS]")
doc.add_paragraph("")

# RING EXCHANGE - has some content
doc.add_paragraph("Ring Exchange")
doc.add_paragraph("Officiant: \"These rings are an outward symbol of an inward commitment. They represent the unbroken circle of love.\"")
doc.add_paragraph("[add specific ring vows here]")
doc.add_paragraph("")

# UNITY CEREMONIES - placeholder
doc.add_paragraph("Unity Ceremonies")
doc.add_paragraph("[FILL IN: Unity candle ceremony - describe the lighting, mothers' candles, etc.]")
doc.add_paragraph("")
doc.add_paragraph("[FILL IN: Breaking of the glass - explain significance or just do it?]")
doc.add_paragraph("")

# PRONOUNCEMENT - placeholder
doc.add_paragraph("Pronouncement")
doc.add_paragraph("[standard language or custom??]")
doc.add_paragraph("Officiant: \"By the power vested in me...\"")
doc.add_paragraph("")

# RECESSIONAL - incomplete
doc.add_paragraph("RECESSIONAL")
doc.add_paragraph("[Music: celebration song]")
doc.add_paragraph("Couple exits, followed by wedding party")

doc.add_paragraph("")
doc.add_paragraph("="*50)
doc.add_paragraph("")
doc.add_paragraph("NOTES:")
doc.add_paragraph("- Total ceremony time should be 25-30 minutes")
doc.add_paragraph("- String quartet will play during processional and recessional")
doc.add_paragraph("- Make sure glass is wrapped in cloth napkin for breaking")
doc.add_paragraph("- Unity candle: three taper candles on table (two lit, one unlit)")

doc.save(sys.argv[1])
print(f"Ceremony draft document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_ceremony_draft.py
python3 /tmp/create_ceremony_draft.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Ceremony draft created at: $DOC_PATH"

# Create a reference file with requirements
REQ_PATH="$WORKSPACE_DIR/ceremony_requirements.txt"
cat > "$REQ_PATH" << 'EOF'
INTERFAITH CEREMONY REQUIREMENTS
From: Rev. Sarah Thompson (Officiant)

Required Elements:
1. Processional with music cue (Canon in D by string quartet)
2. Welcome addressing both families/traditions
3. Jewish element: 7th Sheva Brachot blessing (English + transliteration)
4. Two readings (one spiritual, one secular)
5. Personal vows (bride first, then groom)
6. Ring exchange with vows
7. Unity candle ceremony (Catholic tradition)
8. Breaking of the glass (Jewish tradition)
9. Pronouncement
10. Recessional with music cue

Formatting Notes:
- Use heading styles for major sections
- Stage directions should be clearly marked (italic or brackets)
- Include timing estimates for each section
- Total ceremony: 25-30 minutes
- Make it easy to read during the ceremony!

Cultural Sensitivity:
- Hebrew blessing should have transliteration for non-Hebrew speakers
- Explain significance of glass breaking
- Acknowledge both families' traditions in welcome

Sample timing breakdown:
- Processional: 3-4 min
- Welcome: 2 min
- Readings: 5 min
- Vows: 5 min
- Ring exchange: 3 min
- Unity ceremonies: 5 min
- Pronouncement: 2 min
- Recessional: 2 min
EOF

chown ga:ga "$REQ_PATH"
echo "✅ Requirements file created at: $REQ_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_ceremony_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_ceremony_task.log || true
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

echo "=== Interfaith Ceremony Script Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "You are helping Maya & James complete their interfaith wedding ceremony script."
echo "The draft document is open and needs significant work to be ceremony-ready."
echo ""
echo "REQUIRED ACTIONS:"
echo ""
echo "1. FILL ALL PLACEHOLDERS:"
echo "   - Replace all [FILL IN...] with actual ceremony content"
echo "   - Replace all [CHOOSE...] with specific choices"
echo "   - Replace all [??] with specific information"
echo "   - Complete all [...] placeholder sections"
echo ""
echo "2. FORMAT PROPERLY:"
echo "   - Make section headers BOLD (e.g., PROCESSIONAL, VOWS, etc.)"
echo "   - Apply Heading 1 or Heading 2 styles to major sections"
echo "   - Make stage directions ITALIC (music cues, entrances, etc.)"
echo "   - Use consistent formatting throughout"
echo ""
echo "3. ADD REQUIRED CONTENT:"
echo "   - Processional: Music cue 'Canon in D - String Quartet'"
echo "   - Hebrew Blessing: Include Sheva Brachot (7th blessing)"
echo "     * Must include English translation"
echo "     * Must include Hebrew transliteration (e.g., 'Baruch atah...')"
echo "   - Readings: Two complete readings with attributions"
echo "   - Vows: Complete vow text for both Maya and James"
echo "   - Unity Candle: Describe the ceremony"
echo "   - Glass Breaking: Include in ceremony"
echo "   - Pronouncement: Complete declaration"
echo "   - Recessional: Music cue for exit"
echo ""
echo "4. ADD TIMING ESTIMATES:"
echo "   - Each major section should have time estimate [e.g., '3 min']"
echo "   - Right-align or place in brackets"
echo "   - Total should be ~25-30 minutes"
echo ""
echo "5. ENSURE BOTH TRADITIONS:"
echo "   - Jewish: Glass breaking, Hebrew blessing"
echo "   - Catholic: Unity candle ceremony"
echo ""
echo "6. SAVE THE DOCUMENT:"
echo "   - Use 'Save As' or rename to: ceremony_script.docx"
echo "   - Or save normally (Ctrl+S) - either name works"
echo ""
echo "REFERENCE:"
echo "   - See ceremony_requirements.txt in same folder for officiant's specs"
echo ""
echo "GOAL: Create a professional, complete ceremony script that the officiant"
echo "      can confidently read during the actual wedding ceremony."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"