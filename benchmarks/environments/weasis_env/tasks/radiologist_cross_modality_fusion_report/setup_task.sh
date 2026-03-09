#!/bin/bash
echo "=== Setting up radiologist_cross_modality_fusion_report task ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# ---------------------------------------------------------------
# STEP 1: Prepare BOTH CT and MR DICOM data directories
# ---------------------------------------------------------------
CT_STUDY_DIR="/home/ga/DICOM/studies/crossmod_ct"
MR_STUDY_DIR="/home/ga/DICOM/studies/crossmod_mr"
SAMPLE_DIR="/home/ga/DICOM/samples"
EXPORT_DIR="/home/ga/DICOM/exports"

sudo -u ga mkdir -p "$CT_STUDY_DIR"
sudo -u ga mkdir -p "$MR_STUDY_DIR"
sudo -u ga mkdir -p "$EXPORT_DIR"

# --- CT data ---
CT_SAMPLE_DIR="$SAMPLE_DIR/ct_scan"
if [ -d "$CT_SAMPLE_DIR" ] && [ -n "$(ls -A "$CT_SAMPLE_DIR" 2>/dev/null)" ]; then
    echo "Using real CT data from $CT_SAMPLE_DIR"
    sudo -u ga cp -r "$CT_SAMPLE_DIR"/. "$CT_STUDY_DIR/"
else
    echo "Downloading CT DICOM data..."
    TMPZIP="/tmp/crossmod_ct.zip"
    wget -q --timeout=60 "https://www.rubomedical.com/dicom_files/dicom_viewer_0002.zip" -O "$TMPZIP"
    if [ -f "$TMPZIP" ] && [ -s "$TMPZIP" ]; then
        sudo -u ga unzip -q -o "$TMPZIP" -d "$CT_STUDY_DIR/" 2>/dev/null || true
        rm -f "$TMPZIP"
    else
        echo "ERROR: Could not obtain CT DICOM data."
        exit 1
    fi
fi

# --- MR data ---
MR_SAMPLE_DIR="$SAMPLE_DIR/mr_scan"
if [ -d "$MR_SAMPLE_DIR" ] && [ -n "$(ls -A "$MR_SAMPLE_DIR" 2>/dev/null)" ]; then
    echo "Using real MR data from $MR_SAMPLE_DIR"
    sudo -u ga cp -r "$MR_SAMPLE_DIR"/. "$MR_STUDY_DIR/"
else
    echo "Downloading MR DICOM data..."
    TMPZIP="/tmp/crossmod_mr.zip"
    wget -q --timeout=60 "https://www.rubomedical.com/dicom_files/dicom_viewer_0003.zip" -O "$TMPZIP"
    if [ -f "$TMPZIP" ] && [ -s "$TMPZIP" ]; then
        sudo -u ga unzip -q -o "$TMPZIP" -d "$MR_STUDY_DIR/" 2>/dev/null || true
        rm -f "$TMPZIP"
    else
        echo "ERROR: Could not obtain MR DICOM data."
        exit 1
    fi
fi

chown -R ga:ga "$CT_STUDY_DIR"
chown -R ga:ga "$MR_STUDY_DIR"
chown -R ga:ga "$EXPORT_DIR"

CT_COUNT=$(find "$CT_STUDY_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" -o ! -name "*.*" \) 2>/dev/null | head -500 | wc -l)
MR_COUNT=$(find "$MR_STUDY_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" -o ! -name "*.*" \) 2>/dev/null | head -500 | wc -l)
echo "CT DICOM files: $CT_COUNT, MR DICOM files: $MR_COUNT"

# ---------------------------------------------------------------
# STEP 2: Remove stale output files
# ---------------------------------------------------------------
rm -f "$EXPORT_DIR"/ct_crossmod*.png 2>/dev/null || true
rm -f "$EXPORT_DIR"/mr_crossmod*.png 2>/dev/null || true
rm -f "$EXPORT_DIR"/crossmodality_report.txt 2>/dev/null || true

# ---------------------------------------------------------------
# STEP 3: Record baseline and timestamp
# ---------------------------------------------------------------
echo "${CT_COUNT}_${MR_COUNT}" > /tmp/radiologist_crossmod_initial
date +%s > /tmp/radiologist_crossmod_start_ts

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

# Pre-position: launch Weasis WITH the CT data loaded
CT_FIRST=$(find "$CT_STUDY_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)
if [ -z "$CT_FIRST" ]; then
    CT_FIRST=$(find "$CT_STUDY_DIR" -type f ! -name ".*" 2>/dev/null | head -1)
fi

if [ -n "$CT_FIRST" ]; then
    su - ga -c "DISPLAY=:1 $WEASIS_CMD '$CT_FIRST' > /tmp/weasis_ga.log 2>&1 &"
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
take_screenshot /tmp/radiologist_crossmod_start_screenshot.png

echo "=== Setup Complete ==="
echo "CT data: $CT_STUDY_DIR ($CT_COUNT files)"
echo "MR data: $MR_STUDY_DIR ($MR_COUNT files)"
echo "Export targets: $EXPORT_DIR/ct_crossmod.png, $EXPORT_DIR/mr_crossmod.png"
echo "Report target: $EXPORT_DIR/crossmodality_report.txt"
