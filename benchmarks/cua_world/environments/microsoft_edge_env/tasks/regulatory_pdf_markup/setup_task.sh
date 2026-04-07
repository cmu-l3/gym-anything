#!/bin/bash
# setup_task.sh - Pre-task hook for regulatory_pdf_markup
# Prepares the PDF document and ensures clean state

set -e

echo "=== Setting up Regulatory PDF Markup Task ==="

# Source utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Kill existing Edge instances to ensure clean start
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2

# 2. Prepare Source Data
DOCS_DIR="/home/ga/Documents"
SOURCE_PDF="$DOCS_DIR/whdfs28a.pdf"
mkdir -p "$DOCS_DIR"

# Download the real FMLA fact sheet
if [ ! -f "$SOURCE_PDF" ]; then
    echo "Downloading source PDF..."
    # Try primary source
    curl -L -o "$SOURCE_PDF" "https://www.dol.gov/sites/dolgov/files/WHD/legacy/files/whdfs28a.pdf" || \
    # Fallback to a local asset or alternative URL if network fails (simulated here with a simple PDF creation if curl fails)
    curl -L -o "$SOURCE_PDF" "https://raw.githubusercontent.com/mozilla/pdf.js/master/test/pdfs/tracemonkey.pdf" 
    
    # Ensure it's owned by ga
    chown ga:ga "$SOURCE_PDF"
fi

# 3. Clean previous outputs
OUTPUT_PDF="/home/ga/Desktop/FMLA_FactSheet_Reviewed.pdf"
rm -f "$OUTPUT_PDF"

# 4. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch Edge (optional, agent can launch it, but nice to have it ready)
# We launch to the new tab page so the agent has to explicitly open the file
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    --start-maximized \
    > /tmp/edge.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Focus and Maximize
DISPLAY=:1 wmctrl -r "Microsoft Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Microsoft Edge" 2>/dev/null || true

# 6. Take Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="