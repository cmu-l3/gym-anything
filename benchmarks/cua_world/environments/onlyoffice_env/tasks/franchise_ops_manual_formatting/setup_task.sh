#!/bin/bash
set -e
echo "=== Setting up Franchise Ops Manual Formatting Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean workspace and kill any existing ONLYOFFICE instances
cleanup_temp_files
kill_onlyoffice ga
sleep 1

# Ensure directories exist
TARGET_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$TARGET_DIR"

DRAFT_PATH="$TARGET_DIR/pct_boh_manual_draft.docx"
FINAL_PATH="$TARGET_DIR/pct_boh_manual_final.docx"

# Remove any existing files from previous runs
rm -f "$DRAFT_PATH" "$FINAL_PATH" 2>/dev/null || true

# Generate the initial raw DOCX using Python (ensures it is a valid file but unformatted)
cat > /tmp/generate_draft.py << 'PYEOF'
import sys
from docx import Document

doc = Document()

# Remove default spacing so it looks very raw
style = doc.styles['Normal']
style.font.name = 'Arial'
style.font.size = 127000  # ~10pt

paragraphs = [
    "PACIFIC COAST TACOS - BACK OF HOUSE OPERATIONS",
    "",
    "1.0 MORNING PREP",
    "1.1 Produce Station",
    "All produce must be washed thoroughly in the prep sink before processing. Ensure all cutting boards are sanitized before use.",
    "CRITICAL SAFETY: Always use cut-resistant gloves when dicing tomatoes or slicing onions.",
    "1.2 Prep Recipes",
    "Follow standard recipe cards for mild and hot salsa. Do not deviate from the specified ratios of cilantro and lime juice.",
    "",
    "2.0 LINE ASSEMBLY",
    "2.1 Protein Station",
    "Hold hot proteins at 140F minimum in the steam table. Stir frequently to maintain consistent temperature.",
    "CRITICAL SAFETY: Chicken must reach an internal temperature of 165F for 15 seconds before serving.",
    "2.2 Toppings Station",
    "Keep cold items properly iced. Swap out deep pans every 4 hours or when temperature climbs above 41F.",
    "",
    "3.0 CLOSING PROCEDURES",
    "3.1 Logs",
    "Empty all trash, sweep floors, and scrub the line with designated floor cleaner.",
    "CRITICAL SAFETY: All sanitation buckets must test between 200-400 ppm quat sanitizer before end of shift.",
    "",
    "Temperature Log Requirements",
    "Item, Frequency, Target Temp",
    "Cold Holding, Every 4 Hours, < 41F",
    "Hot Holding, Every 4 Hours, > 135F",
    "Cooling, 2 Hours, 135F to 70F"
]

for p in paragraphs:
    doc.add_paragraph(p)

doc.save(sys.argv[1])
PYEOF

python3 /tmp/generate_draft.py "$DRAFT_PATH"
chown ga:ga "$DRAFT_PATH"

echo "Draft document created at $DRAFT_PATH"

# Launch ONLYOFFICE Document Editor with the file
echo "Launching ONLYOFFICE..."
sudo -u ga DISPLAY=:1 onlyoffice-desktopeditors "$DRAFT_PATH" > /tmp/onlyoffice_task.log 2>&1 &

# Wait for window to appear
echo "Waiting for ONLYOFFICE window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "ONLYOFFICE\|Desktop Editors"; then
        break
    fi
    sleep 1
done

# Maximize and focus the window
sleep 2
WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Final focus
focus_onlyoffice_window || true

# Take initial state screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="