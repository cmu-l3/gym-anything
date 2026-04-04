#!/bin/bash
echo "=== Setting up multimodality_comparison task ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# ---------------------------------------------------------------
# STEP 1: Set up CT and MRI data in separate task-specific directories
# Uses BOTH real CT (rubomedical dicom_viewer_0002) and
# real MRI (rubomedical dicom_viewer_0003) — making this task
# meaningfully different from ct_cardiac and mpr_kidney tasks
# ---------------------------------------------------------------
CT_DIR="/home/ga/DICOM/studies/pmr_ct"
MRI_DIR="/home/ga/DICOM/studies/pmr_mri"
SAMPLE_DIR="/home/ga/DICOM/samples"

sudo -u ga mkdir -p "$CT_DIR"
sudo -u ga mkdir -p "$MRI_DIR"
sudo -u ga mkdir -p "/home/ga/DICOM/exports"

# Set up CT data
CT_SAMPLE_DIR="$SAMPLE_DIR/ct_scan"
if [ -d "$CT_SAMPLE_DIR" ] && [ -n "$(ls -A "$CT_SAMPLE_DIR" 2>/dev/null)" ]; then
    echo "Using existing CT sample for PMR CT"
    sudo -u ga cp -r "$CT_SAMPLE_DIR"/. "$CT_DIR/"
else
    echo "Downloading CT data..."
    wget -q --timeout=60 "https://www.rubomedical.com/dicom_files/dicom_viewer_0002.zip" -O /tmp/pmr_ct.zip
    if [ -s /tmp/pmr_ct.zip ]; then
        sudo -u ga unzip -q -o /tmp/pmr_ct.zip -d "$CT_DIR/" 2>/dev/null || true
        rm -f /tmp/pmr_ct.zip
    else
        echo "ERROR: Could not obtain CT DICOM data."
        exit 1
    fi
fi

# Set up MRI data (different from CT — distinct modality)
MRI_SAMPLE_DIR="$SAMPLE_DIR/mr_scan"
if [ -d "$MRI_SAMPLE_DIR" ] && [ -n "$(ls -A "$MRI_SAMPLE_DIR" 2>/dev/null)" ]; then
    echo "Using existing MRI sample for PMR MRI"
    sudo -u ga cp -r "$MRI_SAMPLE_DIR"/. "$MRI_DIR/"
else
    echo "Downloading MRI data..."
    wget -q --timeout=60 "https://www.rubomedical.com/dicom_files/dicom_viewer_0003.zip" -O /tmp/pmr_mri.zip
    if [ -s /tmp/pmr_mri.zip ]; then
        sudo -u ga unzip -q -o /tmp/pmr_mri.zip -d "$MRI_DIR/" 2>/dev/null || true
        rm -f /tmp/pmr_mri.zip
    else
        echo "ERROR: Could not obtain MRI DICOM data."
        exit 1
    fi
fi

chown -R ga:ga "$CT_DIR"
chown -R ga:ga "$MRI_DIR"
chown -R ga:ga "/home/ga/DICOM/exports"

CT_COUNT=$(find "$CT_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | wc -l)
MRI_COUNT=$(find "$MRI_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | wc -l)
echo "CT DICOM files: $CT_COUNT"
echo "MRI DICOM files: $MRI_COUNT"

if [ "$CT_COUNT" -eq 0 ] || [ "$MRI_COUNT" -eq 0 ]; then
    echo "WARNING: One or both datasets are missing DICOM files"
fi

# ---------------------------------------------------------------
# STEP 2: Clean stale outputs BEFORE recording timestamp
# ---------------------------------------------------------------
rm -f /home/ga/DICOM/exports/comparison_view.png 2>/dev/null || true
rm -f /home/ga/DICOM/exports/comparison_report.txt 2>/dev/null || true

# ---------------------------------------------------------------
# STEP 3: Record baseline and timestamp
# ---------------------------------------------------------------
echo "${CT_COUNT},${MRI_COUNT}" > /tmp/multimodality_initial_counts
date +%s > /tmp/multimodality_start_ts

# ---------------------------------------------------------------
# STEP 4: Launch Weasis fresh
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
take_screenshot /tmp/multimodality_start_screenshot.png

echo "=== Setup Complete ==="
echo "CT data: $CT_DIR ($CT_COUNT files)"
echo "MRI data: $MRI_DIR ($MRI_COUNT files)"
echo "Load BOTH in Weasis and set up side-by-side comparison"
