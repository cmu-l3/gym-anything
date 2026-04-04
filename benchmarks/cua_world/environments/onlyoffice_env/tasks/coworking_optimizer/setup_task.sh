#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Coworking Optimizer Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create task instructions on Desktop
INSTRUCTIONS_PATH="/home/ga/Desktop/TASK_INSTRUCTIONS.txt"

cat > "$INSTRUCTIONS_PATH" << 'EOF'
═══════════════════════════════════════════════════════════════
COWORKING SPACE COMPARISON TASK
═══════════════════════════════════════════════════════════════

SCENARIO:
You are helping Maya, a freelance developer, compare 5 coworking 
spaces with different pricing models to find the best value.

CREATE SPREADSHEET: 
/home/ga/Documents/Spreadsheets/coworking_comparison.xlsx

═══════════════════════════════════════════════════════════════
COLUMN STRUCTURE:
═══════════════════════════════════════════════════════════════

Row 1 (Headers):
  A: Space Name
  B: Pricing Model  
  C: Base Price
  D: Units/Coverage
  E: Cost Per Visit (CALCULATED)
  F: Monthly Cost @ 8 visits (CALCULATED)
  G: Monthly Cost @ 10 visits (CALCULATED)

═══════════════════════════════════════════════════════════════
DATA TO ENTER (Rows 2-6):
═══════════════════════════════════════════════════════════════

1. WorkHub Downtown
   - Pricing Model: Day Pass
   - Base Price: $25
   - Units: per day

2. Creative Collective
   - Pricing Model: Punch Card
   - Base Price: $200
   - Units: 10 visits

3. Flex Office Plaza
   - Pricing Model: Monthly Flex
   - Base Price: $150
   - Units: 6 days/month

4. Startup Loft
   - Pricing Model: Monthly Flex
   - Base Price: $180
   - Units: 8 days/month

5. The Commons
   - Pricing Model: Day Pass
   - Base Price: $30
   - Units: per day

═══════════════════════════════════════════════════════════════
CALCULATION INSTRUCTIONS (USE FORMULAS!):
═══════════════════════════════════════════════════════════════

COLUMN E - Cost Per Visit:
  • Day Pass: Base Price directly
  • Punch Card: Base Price ÷ Number of visits
  • Monthly Flex: Base Price ÷ Included days

COLUMN F - Monthly Cost @ 8 visits:
  • Day Pass/Punch Card: Cost per visit × 8
  • Monthly Flex: 
    - If 8 ≤ included days: Base Price only
    - If 8 > included days: Base + (extra days × cost per visit)

COLUMN G - Monthly Cost @ 10 visits:
  • Same logic as Column F, but for 10 visits

═══════════════════════════════════════════════════════════════
EXAMPLE CALCULATION:
═══════════════════════════════════════════════════════════════

Flex Office Plaza ($150 for 6 days):
  • Cost per visit = $150 ÷ 6 = $25
  • @ 8 visits: $150 + (2 extra × $25) = $200
  • @ 10 visits: $150 + (4 extra × $25) = $250

═══════════════════════════════════════════════════════════════
IMPORTANT:
  ✓ Use FORMULAS for calculations (not manual)
  ✓ Save file when done (Ctrl+S)
  ✓ All monetary values should be numbers (not text)
═══════════════════════════════════════════════════════════════
EOF

chown ga:ga "$INSTRUCTIONS_PATH"

echo "✅ Task instructions created at: $INSTRUCTIONS_PATH"

# Target spreadsheet path (will be created by agent)
SHEET_PATH="$WORKSPACE_DIR/coworking_comparison.xlsx"

# Launch ONLYOFFICE Spreadsheet Editor with a blank workbook
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:spreadsheet > /tmp/onlyoffice_coworking_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_coworking_task.log || true
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

# Give agent time to see the interface
sleep 2

echo "=== Coworking Optimizer Task Setup Complete ==="
echo ""
echo "📋 Task Instructions available on Desktop"
echo "📊 Agent should create: $SHEET_PATH"
echo ""
echo "Expected Results:"
echo "  • WorkHub Downtown: $25/visit → $200 @ 8 visits → $250 @ 10 visits"
echo "  • Creative Collective: $20/visit → $160 @ 8 visits → $200 @ 10 visits"
echo "  • Flex Office Plaza: $25/visit → $200 @ 8 visits → $250 @ 10 visits"
echo "  • Startup Loft: $22.50/visit → $180 @ 8 visits → $225 @ 10 visits"
echo "  • The Commons: $30/visit → $240 @ 8 visits → $300 @ 10 visits"