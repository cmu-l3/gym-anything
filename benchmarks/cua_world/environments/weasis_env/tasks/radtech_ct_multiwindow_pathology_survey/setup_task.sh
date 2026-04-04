#!/bin/bash
echo "=== Setting up radtech_ct_multiwindow_pathology_survey task ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# ---------------------------------------------------------------
# STEP 1: Prepare task-specific DICOM data directory
# ---------------------------------------------------------------
STUDY_DIR="/home/ga/DICOM/studies/multiwindow_ct"
SAMPLE_DIR="/home/ga/DICOM/samples"
EXPORT_DIR="/home/ga/DICOM/exports"

sudo -u ga mkdir -p "$STUDY_DIR"
sudo -u ga mkdir -p "$EXPORT_DIR"

# Check if real CT data exists from post_start download
CT_SAMPLE_DIR="$SAMPLE_DIR/ct_scan"
if [ -d "$CT_SAMPLE_DIR" ] && [ -n "$(ls -A "$CT_SAMPLE_DIR" 2>/dev/null)" ]; then
    echo "Using real CT data from $CT_SAMPLE_DIR"
    sudo -u ga cp -r "$CT_SAMPLE_DIR"/. "$STUDY_DIR/"
    echo "Copied CT data to $STUDY_DIR"
else
    # Try downloading directly
    echo "Downloading real CT DICOM data..."
    TMPZIP="/tmp/multiwindow_ct_sample.zip"
    wget -q --timeout=60 "https://www.rubomedical.com/dicom_files/dicom_viewer_0002.zip" -O "$TMPZIP"
    if [ -f "$TMPZIP" ] && [ -s "$TMPZIP" ]; then
        sudo -u ga unzip -q -o "$TMPZIP" -d "$STUDY_DIR/" 2>/dev/null || true
        rm -f "$TMPZIP"
        echo "Downloaded and extracted CT data to $STUDY_DIR"
    else
        echo "ERROR: Could not obtain real CT DICOM data."
        exit 1
    fi
fi

# Ensure correct ownership
chown -R ga:ga "$STUDY_DIR"
chown -R ga:ga "$EXPORT_DIR"

# Verify data exists
DICOM_COUNT=$(find "$STUDY_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" -o ! -name "*.*" \) 2>/dev/null | head -500 | wc -l)
echo "CT DICOM files found: $DICOM_COUNT"

# ---------------------------------------------------------------
# STEP 2: Remove stale output files BEFORE recording timestamp
# ---------------------------------------------------------------
rm -f "$EXPORT_DIR"/lung_window*.png 2>/dev/null || true
rm -f "$EXPORT_DIR"/bone_window*.png 2>/dev/null || true
rm -f "$EXPORT_DIR"/soft_tissue*.png 2>/dev/null || true
rm -f "$EXPORT_DIR"/mediastinal*.png 2>/dev/null || true
rm -f "$EXPORT_DIR"/multiwindow_survey_report.txt 2>/dev/null || true
# Also remove any generic PNG exports that might contaminate
rm -f "$EXPORT_DIR"/*.png 2>/dev/null || true
rm -f "$EXPORT_DIR"/*.txt 2>/dev/null || true

# ---------------------------------------------------------------
# STEP 3: Record baseline state and task start timestamp
# ---------------------------------------------------------------
echo "$DICOM_COUNT" > /tmp/radtech_multiwindow_initial_count
date +%s > /tmp/radtech_multiwindow_start_ts

echo "Baseline: $DICOM_COUNT CT slices available"

# ---------------------------------------------------------------
# STEP 4: Kill any existing Weasis instance and relaunch
# ---------------------------------------------------------------
pkill -f weasis 2>/dev/null || true
sleep 2

echo "Launching Weasis..."
if command -v /snap/bin/weasis &>/dev/null; then
    WEASIS_CMD="/snap/bin/weasis"
elif command -v weasis &>/dev/null; then
    WEASIS_CMD="weasis"
else
    echo "ERROR: Weasis not found"
    exit 1
fi

# Pre-position: launch Weasis WITH the DICOM data loaded
FIRST_DICOM=$(find "$STUDY_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)
if [ -z "$FIRST_DICOM" ]; then
    FIRST_DICOM=$(find "$STUDY_DIR" -type f ! -name ".*" 2>/dev/null | head -1)
fi

if [ -n "$FIRST_DICOM" ]; then
    su - ga -c "DISPLAY=:1 $WEASIS_CMD '$FIRST_DICOM' > /tmp/weasis_ga.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 $WEASIS_CMD > /tmp/weasis_ga.log 2>&1 &"
fi
sleep 8

# Wait for Weasis window
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "weasis"; then
        echo "Weasis window detected"
        break
    fi
    sleep 2
done

# Dismiss first-run dialog if it appears
sleep 2
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "First Time\|disclaimer\|accept"; then
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
fi

# Maximize Weasis window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i weasis | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/radtech_multiwindow_start_screenshot.png

echo "=== Setup Complete ==="
echo "CT data in: $STUDY_DIR"
echo "Export target directory: $EXPORT_DIR"
echo "Report target: $EXPORT_DIR/multiwindow_survey_report.txt"
