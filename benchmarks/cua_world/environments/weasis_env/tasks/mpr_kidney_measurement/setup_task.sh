#!/bin/bash
echo "=== Setting up mpr_kidney_measurement task ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# ---------------------------------------------------------------
# STEP 1: Set up task-specific DICOM data
# Uses REAL CT data (rubomedical.com publicly available sample)
# This data is distinct from chest_ct — uses the same source but
# places it in a urogram-specific directory with different study context
# ---------------------------------------------------------------
STUDY_DIR="/home/ga/DICOM/studies/ct_urogram"
SAMPLE_DIR="/home/ga/DICOM/samples"

sudo -u ga mkdir -p "$STUDY_DIR"
sudo -u ga mkdir -p "/home/ga/DICOM/exports"

# First try the already-downloaded MR sample since urologists also review MRI
# For this task we use the CT sample
CT_SAMPLE_DIR="$SAMPLE_DIR/ct_scan"
if [ -d "$CT_SAMPLE_DIR" ] && [ -n "$(ls -A "$CT_SAMPLE_DIR" 2>/dev/null)" ]; then
    echo "Using real CT data from $CT_SAMPLE_DIR"
    sudo -u ga cp -r "$CT_SAMPLE_DIR"/. "$STUDY_DIR/"
else
    echo "Downloading real CT DICOM data for urogram task..."
    TMPZIP="/tmp/ct_urogram_sample.zip"
    wget -q --timeout=60 "https://www.rubomedical.com/dicom_files/dicom_viewer_0002.zip" -O "$TMPZIP"
    if [ -f "$TMPZIP" ] && [ -s "$TMPZIP" ]; then
        sudo -u ga unzip -q -o "$TMPZIP" -d "$STUDY_DIR/" 2>/dev/null || true
        rm -f "$TMPZIP"
        echo "Downloaded CT urogram data to $STUDY_DIR"
    else
        echo "ERROR: Could not obtain real CT DICOM data. Please ensure network access."
        exit 1
    fi
fi

chown -R ga:ga "$STUDY_DIR"
chown -R ga:ga "/home/ga/DICOM/exports"

DICOM_COUNT=$(find "$STUDY_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | wc -l)
echo "CT DICOM files in urogram directory: $DICOM_COUNT"

# ---------------------------------------------------------------
# STEP 2: Remove stale output files BEFORE recording timestamp
# ---------------------------------------------------------------
rm -f /home/ga/DICOM/exports/mpr_renal.png 2>/dev/null || true
rm -f /home/ga/DICOM/exports/renal_report.txt 2>/dev/null || true

# ---------------------------------------------------------------
# STEP 3: Record baseline and timestamp
# ---------------------------------------------------------------
echo "$DICOM_COUNT" > /tmp/mpr_kidney_initial_count
date +%s > /tmp/mpr_kidney_start_ts

# ---------------------------------------------------------------
# STEP 4: Kill any existing Weasis and relaunch clean
# ---------------------------------------------------------------
pkill -f weasis 2>/dev/null || true
sleep 2

if command -v /snap/bin/weasis &>/dev/null; then
    WEASIS_CMD="/snap/bin/weasis"
elif command -v weasis &>/dev/null; then
    WEASIS_CMD="weasis"
else
    echo "ERROR: Weasis not found"
    exit 1
fi

echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 $WEASIS_CMD > /tmp/weasis_ga.log 2>&1 &"
sleep 8

for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "weasis"; then
        echo "Weasis window detected"
        break
    fi
    sleep 2
done

sleep 2
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "First Time\|disclaimer\|accept"; then
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
fi

WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i weasis | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/mpr_kidney_start_screenshot.png

echo "=== Setup Complete ==="
echo "CT urogram data: $STUDY_DIR ($DICOM_COUNT slices)"
echo "Export targets: /home/ga/DICOM/exports/mpr_renal.png"
echo "              : /home/ga/DICOM/exports/renal_report.txt"
