#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Medication Reference Sheet Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the source information file with medication details
SOURCE_FILE="$WORKSPACE_DIR/medication_info.txt"

cat > "$SOURCE_FILE" << 'EOF'
MARGARET CHEN - MEDICATION INFORMATION
========================================
(Compiled from prescription bottles and pharmacist notes)

MEDICATIONS:
------------

1. Metformin 500mg
   - Take twice daily with meals (breakfast & dinner)
   - Purpose: Type 2 Diabetes control
   - Important: Take with food to reduce stomach upset

2. Lisinopril 10mg
   - Take once daily in morning
   - Purpose: Blood pressure management
   - Note: May cause dizziness when standing up quickly

3. Atorvastatin 20mg
   - Take once daily at bedtime
   - Purpose: Cholesterol control
   - ⚠️ CRITICAL WARNING: DO NOT consume grapefruit or grapefruit juice
   - Serious drug interaction - can cause muscle damage and liver problems

4. Levothyroxine 75mcg
   - Take once daily in morning
   - Purpose: Thyroid hormone replacement
   - ⚠️ IMPORTANT: Take 30-60 minutes BEFORE breakfast on EMPTY STOMACH
   - Do not take with calcium or iron supplements
   - Wait at least 1 hour before taking other medications

5. Aspirin 81mg (baby aspirin)
   - Take once daily in morning
   - Purpose: Heart health / blood thinner
   - Note: Inform any dentist or surgeon before procedures

EMERGENCY CONTACTS:
-------------------
- Daughter: Sarah Chen - (555) 123-4567
- Pharmacist: MedCare Pharmacy - (555) 987-6543
- Dr. Williams (Primary Care): (555) 234-5678
- Poison Control: 1-800-222-1222

CRITICAL DRUG INTERACTIONS:
----------------------------
- Atorvastatin + Grapefruit = DANGEROUS (muscle damage, liver problems)
- Levothyroxine must be taken alone on empty stomach
- Aspirin is a blood thinner - inform all healthcare providers

ADDITIONAL NOTES:
-----------------
- Keep medication list updated after each doctor visit
- Print this reference and keep on refrigerator
- Bring this list to all medical appointments
- Check expiration dates monthly
- Use pill organizer to prevent missed doses

Last Updated: January 2024
EOF

chown ga:ga "$SOURCE_FILE"

echo "✅ Medication information file created at: $SOURCE_FILE"

# Launch ONLYOFFICE Document Editor (will open blank document)
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors > /tmp/onlyoffice_medication_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_medication_task.log || true
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

echo "=== Medication Reference Sheet Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "======================================================"
echo "You need to create a medication reference document for Margaret Chen,"
echo "a 72-year-old with vision impairment who takes multiple medications."
echo ""
echo "📖 Source Information:"
echo "  - Read medication details from: $SOURCE_FILE"
echo ""
echo "📝 Document Requirements:"
echo ""
echo "1. TITLE (at top of document):"
echo "   - Text: 'Medication Reference - Margaret Chen'"
echo "   - Font size: 16pt or larger"
echo "   - Bold formatting"
echo "   - Center-aligned"
echo ""
echo "2. MEDICATIONS TABLE:"
echo "   - Create a table with 4 columns:"
echo "     * Medication Name"
echo "     * Dosage"
echo "     * Time of Day"
echo "     * Purpose"
echo "   - Add 5 medication rows (from source file):"
echo "     * Metformin 500mg"
echo "     * Lisinopril 10mg"
echo "     * Atorvastatin 20mg"
echo "     * Levothyroxine 75mcg"
echo "     * Aspirin 81mg"
echo ""
echo "3. WARNINGS SECTION:"
echo "   - Heading: 'IMPORTANT WARNINGS' or '⚠️ IMPORTANT WARNINGS' (bold, 14pt+)"
echo "   - Include these critical warnings (in bold):"
echo "     * NO GRAPEFRUIT (or 'Avoid grapefruit') - for Atorvastatin"
echo "     * Take on empty stomach - for Levothyroxine"
echo ""
echo "4. EMERGENCY CONTACTS:"
echo "   - Heading: 'Emergency Contact' (bold)"
echo "   - List:"
echo "     * Daughter: Sarah Chen - (555) 123-4567"
echo "     * Pharmacist: MedCare Pharmacy - (555) 987-6543"
echo ""
echo "💾 Save the document as:"
echo "   /home/ga/Documents/TextDocuments/medication_reference.docx"
echo ""
echo "⏱️  Estimated time: 8-12 minutes"
echo "======================================================"