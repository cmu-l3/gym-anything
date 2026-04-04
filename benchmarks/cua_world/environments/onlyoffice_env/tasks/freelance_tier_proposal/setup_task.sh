#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Freelance Tier Proposal Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# The agent will create the document from scratch
# We just need to launch ONLYOFFICE with a blank document
DOC_PATH="$WORKSPACE_DIR/client_proposal.docx"

# Remove any existing proposal document to ensure fresh start
if [ -f "$DOC_PATH" ]; then
    rm -f "$DOC_PATH"
fi

echo "📝 Task: Create a client proposal with 3 pricing tiers"

# Launch ONLYOFFICE Document Editor (blank)
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors > /tmp/onlyoffice_proposal_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_proposal_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Freelance Tier Proposal Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "You are a freelance designer who needs to create a formal proposal for a nonprofit client."
echo "They want to see 3 different service packages at different price points."
echo ""
echo "📝 YOUR TASK:"
echo "Create a professional proposal document that includes:"
echo ""
echo "  ✓ A clear title (e.g., 'Service Proposal', 'Pricing Options', etc.)"
echo "  ✓ THREE distinct pricing tiers with different names, such as:"
echo "     - Basic / Standard / Premium"
echo "     - Tier 1 / Tier 2 / Tier 3"
echo "     - Bronze / Silver / Gold"
echo "     - Option A / Option B / Option C"
echo "     - Essential / Professional / Complete"
echo ""
echo "  ✓ Each tier should include:"
echo "     - A clear tier name/label"
echo "     - A price (in dollars, e.g., \$500, \$1000, \$1500)"
echo "     - What's included (deliverables/services)"
echo ""
echo "  ✓ Use professional formatting:"
echo "     - Create a table with rows for each tier, OR"
echo "     - Use formatted lists (bullet points or numbered lists)"
echo "     - Apply headings, bold, or other formatting for clarity"
echo ""
echo "  ✓ Save the document as: /home/ga/Documents/TextDocuments/client_proposal.docx"
echo "     (Use Ctrl+S and navigate to the correct location)"
echo ""
echo "💡 TIP: Think about what a real client would want to see - clear options,"
echo "    obvious price differences, and easy-to-compare packages."
echo ""