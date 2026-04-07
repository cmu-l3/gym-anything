#!/bin/bash
set -euo pipefail

echo "=== Setting up Semiconductor SPC Control Chart Analysis Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Source utility functions if available, otherwise define polyfills
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    cleanup_temp_files() { rm -f /tmp/onlyoffice_*.log 2>/dev/null || true; }
    kill_onlyoffice() { pkill -f "onlyoffice-desktopeditors" 2>/dev/null || true; }
fi

cleanup_temp_files
kill_onlyoffice ga || true
sleep 1

# Create directories
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$DOCS_DIR"

# =====================================================================
# 1. Generate Authentic-Looking Wafer Data
# (Contains 3 specific out-of-control lots: 16, 25, 26)
# =====================================================================
DATA_CSV="$WORKSPACE_DIR/wafer_thickness_data.csv"
cat > "$DATA_CSV" << 'EOF'
Lot_ID,Wafer_1,Wafer_2,Wafer_3,Wafer_4,Wafer_5
LOT_001,438.2,442.1,439.5,445.0,437.8
LOT_002,440.1,444.3,438.9,441.2,439.6
LOT_003,439.5,435.6,441.0,443.2,440.8
LOT_004,442.3,440.1,437.9,439.4,441.7
LOT_005,441.8,438.4,440.5,442.9,436.1
LOT_006,437.5,441.2,439.8,440.1,442.4
LOT_007,439.9,443.5,438.1,440.7,439.2
LOT_008,440.2,437.8,441.6,439.3,444.1
LOT_009,441.5,439.1,440.8,438.6,442.0
LOT_010,438.9,442.5,440.3,439.7,441.2
LOT_011,439.4,438.2,442.1,440.6,437.9
LOT_012,440.8,441.5,439.2,443.0,438.5
LOT_013,442.1,439.6,440.9,438.1,441.4
LOT_014,438.5,440.2,442.8,439.5,441.0
LOT_015,440.3,441.8,438.7,442.4,439.1
LOT_016,449.2,448.5,451.0,450.3,447.8
LOT_017,441.0,439.4,442.5,438.9,440.6
LOT_018,439.7,441.1,438.4,440.2,442.8
LOT_019,440.5,438.8,441.3,439.6,440.1
LOT_020,442.6,440.4,439.1,441.8,438.5
LOT_021,438.2,441.7,440.5,439.0,442.3
LOT_022,440.9,438.5,442.0,441.2,439.7
LOT_023,441.4,440.2,438.9,442.5,439.1
LOT_024,439.6,442.8,440.1,438.5,441.0
LOT_025,431.5,429.8,430.4,432.1,428.9
LOT_026,430.2,432.5,429.1,431.8,430.7
LOT_027,440.1,438.7,441.5,439.9,442.2
LOT_028,438.8,441.2,439.6,440.5,438.1
LOT_029,442.0,439.5,441.8,438.4,440.7
LOT_030,439.3,440.9,438.2,442.1,441.5
EOF
chown ga:ga "$DATA_CSV"

# =====================================================================
# 2. Create Constants Reference
# =====================================================================
CONSTANTS_FILE="$DOCS_DIR/spc_constants_reference.txt"
cat > "$CONSTANTS_FILE" << 'EOF'
SEMICONDUCTOR QUALITY ENGINEERING
STATISTICAL PROCESS CONTROL (SPC) CONSTANTS
===========================================
Sample Size (n) = 5 Wafers per Lot

Please use the following standard constants for calculating 3-sigma control limits for X-bar and R charts:

A2 = 0.577
D3 = 0.0
D4 = 2.114

Formulas:
UCL (X-bar) = Grand Mean + (A2 * Average Range)
LCL (X-bar) = Grand Mean - (A2 * Average Range)
UCL (R) = D4 * Average Range
LCL (R) = D3 * Average Range
EOF
chown ga:ga "$CONSTANTS_FILE"

# =====================================================================
# 3. Launch Application
# =====================================================================
# Clean up any potential previous outputs
rm -f "$WORKSPACE_DIR/wafer_spc_analysis.xlsx" 2>/dev/null || true

# Launch OnlyOffice
echo "Starting ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:cell > /tmp/onlyoffice_setup.log 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Desktop Editors\|ONLYOFFICE"; then
        echo "ONLYOFFICE window detected."
        break
    fi
    sleep 1
done

# Maximize and focus window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a :ACTIVE: 2>/dev/null || true
sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="