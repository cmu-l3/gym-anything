#!/bin/bash
echo "=== Setting up neurologist_mri_ventricle_morphometry task ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# ---------------------------------------------------------------
# STEP 1: Prepare task-specific DICOM data directory
# ---------------------------------------------------------------
STUDY_DIR="/home/ga/DICOM/studies/brain_mri_nph"
SAMPLE_DIR="/home/ga/DICOM/samples"
EXPORT_DIR="/home/ga/DICOM/exports"

sudo -u ga mkdir -p "$STUDY_DIR"
sudo -u ga mkdir -p "$EXPORT_DIR"

# Check if real MR data exists from post_start download
MR_SAMPLE_DIR="$SAMPLE_DIR/mr_scan"
if [ -d "$MR_SAMPLE_DIR" ] && [ -n "$(ls -A "$MR_SAMPLE_DIR" 2>/dev/null)" ]; then
    echo "Using real MR brain data from $MR_SAMPLE_DIR"
    sudo -u ga cp -r "$MR_SAMPLE_DIR"/. "$STUDY_DIR/"
    echo "Copied MR data to $STUDY_DIR"
else
    echo "Downloading real MR DICOM data..."
    TMPZIP="/tmp/brain_mri_sample.zip"
    wget -q --timeout=60 "https://www.rubomedical.com/dicom_files/dicom_viewer_0003.zip" -O "$TMPZIP"
    if [ -f "$TMPZIP" ] && [ -s "$TMPZIP" ]; then
        sudo -u ga unzip -q -o "$TMPZIP" -d "$STUDY_DIR/" 2>/dev/null || true
        rm -f "$TMPZIP"
        echo "Downloaded and extracted MR data to $STUDY_DIR"
    else
        echo "ERROR: Could not obtain real MR DICOM data."
        exit 1
    fi
fi

chown -R ga:ga "$STUDY_DIR"
chown -R ga:ga "$EXPORT_DIR"

DICOM_COUNT=$(find "$STUDY_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" -o ! -name "*.*" \) 2>/dev/null | head -500 | wc -l)
echo "MR DICOM files found: $DICOM_COUNT"

# ---------------------------------------------------------------
# STEP 2: Remove stale output files
# ---------------------------------------------------------------
rm -f "$EXPORT_DIR"/evans_index_measurement.png 2>/dev/null || true
rm -f "$EXPORT_DIR"/nph_assessment_report.txt 2>/dev/null || true

# ---------------------------------------------------------------
# STEP 3: Record baseline and timestamp
# ---------------------------------------------------------------
echo "$DICOM_COUNT" > /tmp/neurologist_ventricle_initial_count
date +%s > /tmp/neurologist_ventricle_start_ts

# ---------------------------------------------------------------
# STEP 4: Launch Weasis
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

# Pre-position: launch Weasis WITH the MR data loaded
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
take_screenshot /tmp/neurologist_ventricle_start_screenshot.png

echo "=== Setup Complete ==="
echo "MR data in: $STUDY_DIR"
echo "Export image target: $EXPORT_DIR/evans_index_measurement.png"
echo "Report target: $EXPORT_DIR/nph_assessment_report.txt"
