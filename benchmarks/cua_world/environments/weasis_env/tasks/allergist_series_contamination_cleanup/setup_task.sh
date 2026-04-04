#!/bin/bash
echo "=== Setting up allergist_series_contamination_cleanup task ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# ---------------------------------------------------------------
# STEP 1: Prepare CT data directory
# ---------------------------------------------------------------
STUDY_DIR="/home/ga/DICOM/studies/airway_series"
QUARANTINE_DIR="/home/ga/DICOM/quarantine"
SAMPLE_DIR="/home/ga/DICOM/samples"
EXPORT_DIR="/home/ga/DICOM/exports"

sudo -u ga mkdir -p "$STUDY_DIR"
sudo -u ga mkdir -p "$QUARANTINE_DIR"
sudo -u ga mkdir -p "$EXPORT_DIR"

# Get CT data (legitimate files)
CT_SAMPLE_DIR="$SAMPLE_DIR/ct_scan"
if [ -d "$CT_SAMPLE_DIR" ] && [ -n "$(ls -A "$CT_SAMPLE_DIR" 2>/dev/null)" ]; then
    echo "Copying CT data from $CT_SAMPLE_DIR"
    sudo -u ga cp -r "$CT_SAMPLE_DIR"/. "$STUDY_DIR/"
else
    echo "Downloading CT DICOM data..."
    TMPZIP="/tmp/airway_ct.zip"
    wget -q --timeout=60 "https://www.rubomedical.com/dicom_files/dicom_viewer_0002.zip" -O "$TMPZIP"
    if [ -f "$TMPZIP" ] && [ -s "$TMPZIP" ]; then
        sudo -u ga unzip -q -o "$TMPZIP" -d "$STUDY_DIR/" 2>/dev/null || true
        rm -f "$TMPZIP"
    else
        echo "ERROR: Could not obtain CT DICOM data."
        exit 1
    fi
fi

# Count legitimate CT files
CT_FILE_COUNT=$(find "$STUDY_DIR" -type f 2>/dev/null | wc -l)
echo "Legitimate CT files: $CT_FILE_COUNT"

# ---------------------------------------------------------------
# STEP 2: Inject contaminating MR files into the CT directory
# Copy 4 MR brain files and rename them to blend in
# ---------------------------------------------------------------
MR_SAMPLE_DIR="$SAMPLE_DIR/mr_scan"
CONTAMINANT_COUNT=0

if [ -d "$MR_SAMPLE_DIR" ] && [ -n "$(ls -A "$MR_SAMPLE_DIR" 2>/dev/null)" ]; then
    echo "Injecting MR contaminants from $MR_SAMPLE_DIR"
    # Get 4 MR files to inject
    MR_FILES=$(find "$MR_SAMPLE_DIR" -type f 2>/dev/null | head -4)
    for mrf in $MR_FILES; do
        BASENAME=$(basename "$mrf")
        # Rename to blend in with CT naming pattern
        CONTAMINANT_COUNT=$((CONTAMINANT_COUNT + 1))
        DEST_NAME="imported_slice_${CONTAMINANT_COUNT}.dcm"
        sudo -u ga cp "$mrf" "$STUDY_DIR/$DEST_NAME"
        echo "  Injected contaminant: $DEST_NAME (from $BASENAME)"
    done
else
    # Try downloading MR data
    echo "Downloading MR data for contaminant injection..."
    TMPZIP="/tmp/mr_contaminant.zip"
    wget -q --timeout=60 "https://www.rubomedical.com/dicom_files/dicom_viewer_0003.zip" -O "$TMPZIP"
    if [ -f "$TMPZIP" ] && [ -s "$TMPZIP" ]; then
        TMP_MR="/tmp/mr_contaminant_extract"
        mkdir -p "$TMP_MR"
        unzip -q -o "$TMPZIP" -d "$TMP_MR/" 2>/dev/null || true
        rm -f "$TMPZIP"
        MR_FILES=$(find "$TMP_MR" -type f 2>/dev/null | head -4)
        for mrf in $MR_FILES; do
            CONTAMINANT_COUNT=$((CONTAMINANT_COUNT + 1))
            DEST_NAME="imported_slice_${CONTAMINANT_COUNT}.dcm"
            sudo -u ga cp "$mrf" "$STUDY_DIR/$DEST_NAME"
        done
        rm -rf "$TMP_MR"
    fi
fi

echo "Injected $CONTAMINANT_COUNT MR contaminant files"

# Record contaminant file names for verification
python3 << PYEOF
import json
contaminant_names = [f"imported_slice_{i}.dcm" for i in range(1, $CONTAMINANT_COUNT + 1)]
with open("/tmp/allergist_contaminant_manifest.json", "w") as f:
    json.dump({
        "contaminant_filenames": contaminant_names,
        "contaminant_count": $CONTAMINANT_COUNT,
        "original_ct_count": $CT_FILE_COUNT,
    }, f)
print(f"Manifest: {$CONTAMINANT_COUNT} contaminants, {$CT_FILE_COUNT} legitimate CT files")
PYEOF

chown -R ga:ga "$STUDY_DIR"
chown -R ga:ga "$QUARANTINE_DIR"
chown -R ga:ga "$EXPORT_DIR"

# ---------------------------------------------------------------
# STEP 3: Remove stale output files
# ---------------------------------------------------------------
rm -f "$EXPORT_DIR"/contamination_report.txt 2>/dev/null || true
rm -f "$QUARANTINE_DIR"/* 2>/dev/null || true

# ---------------------------------------------------------------
# STEP 4: Record baseline and timestamp
# ---------------------------------------------------------------
TOTAL_FILES=$(find "$STUDY_DIR" -type f 2>/dev/null | wc -l)
echo "$TOTAL_FILES" > /tmp/allergist_contamination_initial_total
echo "$CT_FILE_COUNT" > /tmp/allergist_contamination_original_ct
echo "$CONTAMINANT_COUNT" > /tmp/allergist_contamination_injected_count
date +%s > /tmp/allergist_contamination_start_ts

echo "Total files in directory: $TOTAL_FILES (CT: $CT_FILE_COUNT + contaminants: $CONTAMINANT_COUNT)"

# ---------------------------------------------------------------
# STEP 5: Launch Weasis with the data pre-loaded
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
take_screenshot /tmp/allergist_contamination_start_screenshot.png

echo "=== Setup Complete ==="
echo "Mixed DICOM data in: $STUDY_DIR"
echo "Quarantine directory: $QUARANTINE_DIR"
echo "Report target: $EXPORT_DIR/contamination_report.txt"
