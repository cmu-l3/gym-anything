#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up pharma_rca_fishbone task ==="

# 1. Create the Deviation Report with realistic pharmaceutical data
cat > /home/ga/Desktop/deviation_report_DEV-2024-0847.txt << 'EOF'
PHARMACO MANUFACTURING - DEVIATION INVESTIGATION REPORT
=====================================================
Deviation ID: DEV-2024-0847
Product: Metformin HCl 500mg Tablets
Batch: BT-20240312
Date: 2024-05-15
Classification: Major
Status: Root Cause Analysis Complete

PROBLEM STATEMENT:
Batch BT-20240312 failed USP dissolution specification at the 30-minute time point.
Specification: Q = 75% at 30 minutes.
Results: 58%, 61%, 59%, 63%, 60%, 58% (Stage 1, n=6).
Root Cause Analysis (Ishikawa/6M Analysis) conducted on 2024-05-16.

INVESTIGATION FINDINGS (ROOT CAUSES):

1. MANPOWER (People)
   - Operator bypassed granulation endpoint check: Log analysis shows the "Granulation Complete" soft-key was pressed 4 minutes early.
   - Night shift had no qualified granulation technician on-site: Due to sudden illness, the lead technician was absent, and a junior operator covered the shift.
   - Sub-cause: SOP unclear on mandatory vs. advisory checks for endpoint determination.

2. MACHINE (Equipment)
   - Tablet press upper punch tooling worn: Inspection of Station #14-22 showed wear 0.08mm beyond tolerance, leading to softer tablets.
   - Fluid bed dryer inlet temperature sensor drifted: Calibration check post-failure showed sensor was reading +4°C higher than actual, causing under-drying.

3. METHOD (Process)
   - Granulation endpoint not validated for >60% RH conditions: The validation study only covered 30-55% RH range.
   - Blending time reduced from 15min to 10min without change control: Optimization trial settings were accidentally left active in the recipes.

4. MATERIAL (Raw Materials)
   - API lot M-7821 particle size D90 = 285μm: Specification is ≤200μm. Coarse particles reduce dissolution rate.
   - Sub-cause: Supplier certificate of analysis not verified on receipt by QC.
   - MCC excipient moisture content 6.8%: Specification is ≤5.0%. High moisture affects binder efficiency.

5. MEASUREMENT (Analysis)
   - Dissolution apparatus paddle height 1mm below USP specification: Found during investigative calibration.
   - HPLC column used 387 injections past requalification limit: Might affect assay values, though less likely to impact physical dissolution.

6. MILIEU (Environment)
   - Granulation suite humidity excursion to 72% RH: Building management system log shows dehumidifier trip during the batch processing.
   - Tablet press room temperature rose to 28°C: Specification is ≤25°C. Heat affects binder activation.

CORRECTIVE AND PREVENTIVE ACTIONS (CAPA):
1. Replace upper punch tooling set for Press #4 immediately.
2. Revise SOP-PRO-055 to make granulation endpoint checks mandatory hard-stops in the HMI.
3. Initiate Change Control CC-2024-102 to validate granulation process at high humidity (60-75% RH).
4. Re-train Warehouse Receiving staff on API PSD specification verification.
5. Calibrate fluid bed dryer temperature sensors monthly (increased from quarterly).

APPROVALS:
Investigation Lead: Sarah Jenkins
QA Manager: Robert Chen
EOF

# Set permissions
chown ga:ga /home/ga/Desktop/deviation_report_DEV-2024-0847.txt
chmod 644 /home/ga/Desktop/deviation_report_DEV-2024-0847.txt

echo "Deviation report created at /home/ga/Desktop/deviation_report_DEV-2024-0847.txt"

# 2. Clean up previous run artifacts
rm -f /home/ga/Desktop/rca_fishbone.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/rca_fishbone.png 2>/dev/null || true

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Launch draw.io (Desktop version)
# Find binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then DRAWIO_BIN="drawio";
elif [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio";
elif [ -f /usr/bin/drawio ]; then DRAWIO_BIN="/usr/bin/drawio"; fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found"
    exit 1
fi

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (Escape creates new blank diagram)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="