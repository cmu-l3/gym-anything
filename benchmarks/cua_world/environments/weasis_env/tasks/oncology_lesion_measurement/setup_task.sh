#!/bin/bash
# Setup script for oncology_lesion_measurement task
# Occupation: Radiologist — RECIST 1.1 tumor response assessment
echo "=== Setting up oncology_lesion_measurement ==="

export DISPLAY=:1

# ------------------------------------------------------------------
# STEP 1: Verify real CT DICOM data is available
# Requires real CT from rubomedical.com (dicom_viewer_0002.zip)
# This should have been downloaded by setup_weasis.sh (post_start hook)
# ------------------------------------------------------------------
CT_SOURCE="/home/ga/DICOM/samples/ct_scan"

if [ ! -d "$CT_SOURCE" ] || [ -z "$(ls -A "$CT_SOURCE" 2>/dev/null)" ]; then
    echo "ERROR: CT DICOM data not found at $CT_SOURCE"
    echo "The post_start hook (setup_weasis.sh) should have downloaded it."
    echo "Cannot set up oncology_lesion_measurement without real CT data."
    exit 1
fi

# ------------------------------------------------------------------
# STEP 2: Create task-specific study directory
# Using CT data — CT is the primary modality for RECIST measurements
# ------------------------------------------------------------------
ONCOLOGY_CT_DIR="/home/ga/DICOM/studies/oncology_ct"
mkdir -p "$ONCOLOGY_CT_DIR"

# Copy the real CT DICOM files into the task study directory
cp -r "$CT_SOURCE"/. "$ONCOLOGY_CT_DIR/"
chown -R ga:ga "$ONCOLOGY_CT_DIR"

CT_FILE_COUNT=$(find "$ONCOLOGY_CT_DIR" -name "*.dcm" -o -name "*.DCM" 2>/dev/null | wc -l)
if [ "$CT_FILE_COUNT" -eq 0 ]; then
    CT_FILE_COUNT=$(find "$ONCOLOGY_CT_DIR" -type f 2>/dev/null | wc -l)
fi
echo "Oncology CT study prepared: $CT_FILE_COUNT files in $ONCOLOGY_CT_DIR"

# ------------------------------------------------------------------
# STEP 3: Create exports directory and remove stale outputs
# Remove BEFORE recording start timestamp
# ------------------------------------------------------------------
mkdir -p /home/ga/DICOM/exports
chown -R ga:ga /home/ga/DICOM/exports

rm -f /home/ga/DICOM/exports/recist_lesion1.png 2>/dev/null || true
rm -f /home/ga/DICOM/exports/recist_lesion2.png 2>/dev/null || true
rm -f /home/ga/DICOM/exports/recist_report.txt 2>/dev/null || true

# ------------------------------------------------------------------
# STEP 4: Record task start timestamp (AFTER cleanup)
# ------------------------------------------------------------------
date +%s > /tmp/oncology_lesion_measurement_start_ts
echo "Task start timestamp recorded: $(cat /tmp/oncology_lesion_measurement_start_ts)"

# ------------------------------------------------------------------
# STEP 5: Ensure Weasis is running
# ------------------------------------------------------------------
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "weasis"; then
    echo "Weasis not running — launching..."
    su - ga -c "DISPLAY=:1 /snap/bin/weasis >> /home/ga/weasis_launch.log 2>&1 &"
    for i in $(seq 1 30); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "weasis"; then
            echo "Weasis window appeared after $((i*2))s"
            break
        fi
        sleep 2
    done
fi

# ------------------------------------------------------------------
# STEP 6: Take initial screenshot
# ------------------------------------------------------------------
sleep 2
DISPLAY=:1 import -window root /tmp/oncology_lesion_measurement_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/oncology_lesion_measurement_start_screenshot.png 2>/dev/null || true

echo "=== oncology_lesion_measurement setup complete ==="
echo "CT data: $ONCOLOGY_CT_DIR ($CT_FILE_COUNT files)"
echo "Export targets: recist_lesion1.png, recist_lesion2.png, recist_report.txt"
