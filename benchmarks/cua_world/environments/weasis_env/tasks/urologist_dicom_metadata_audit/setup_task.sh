#!/bin/bash
echo "=== Setting up urologist_dicom_metadata_audit task ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# ---------------------------------------------------------------
# STEP 1: Prepare DICOM data and inject metadata errors
# ---------------------------------------------------------------
STUDY_DIR="/home/ga/DICOM/studies/renal_audit"
SAMPLE_DIR="/home/ga/DICOM/samples"
EXPORT_DIR="/home/ga/DICOM/exports"

sudo -u ga mkdir -p "$STUDY_DIR"
sudo -u ga mkdir -p "$EXPORT_DIR"

# Get CT data
CT_SAMPLE_DIR="$SAMPLE_DIR/ct_scan"
if [ -d "$CT_SAMPLE_DIR" ] && [ -n "$(ls -A "$CT_SAMPLE_DIR" 2>/dev/null)" ]; then
    echo "Using real CT data from $CT_SAMPLE_DIR"
    sudo -u ga cp -r "$CT_SAMPLE_DIR"/. "$STUDY_DIR/"
else
    echo "Downloading CT DICOM data..."
    TMPZIP="/tmp/renal_audit_ct.zip"
    wget -q --timeout=60 "https://www.rubomedical.com/dicom_files/dicom_viewer_0002.zip" -O "$TMPZIP"
    if [ -f "$TMPZIP" ] && [ -s "$TMPZIP" ]; then
        sudo -u ga unzip -q -o "$TMPZIP" -d "$STUDY_DIR/" 2>/dev/null || true
        rm -f "$TMPZIP"
    else
        echo "ERROR: Could not obtain CT DICOM data."
        exit 1
    fi
fi

chown -R ga:ga "$STUDY_DIR"
chown -R ga:ga "$EXPORT_DIR"

# ---------------------------------------------------------------
# STEP 2: Inject metadata errors into DICOM files using pydicom
# These are the errors the agent must discover and fix
# ---------------------------------------------------------------
echo "Injecting metadata errors into DICOM files..."

# Record original values before corruption
python3 << 'PYEOF'
import os, json

try:
    import pydicom
except ImportError:
    print("pydicom not available, skipping error injection")
    exit(0)

study_dir = "/home/ga/DICOM/studies/renal_audit"
original_values = {}
files_modified = 0

for root, dirs, files in os.walk(study_dir):
    for fname in files:
        fpath = os.path.join(root, fname)
        try:
            ds = pydicom.dcmread(fpath, force=True)
        except Exception:
            continue

        # Record original values from first readable file
        if not original_values:
            original_values = {
                "original_patient_sex": str(getattr(ds, 'PatientSex', 'M')),
                "original_body_part": str(getattr(ds, 'BodyPartExamined', 'ABDOMEN')),
                "original_referring_physician": str(getattr(ds, 'ReferringPhysicianName', 'Dr. Smith')),
            }

        # Inject Error 1: Wrong patient sex (M -> F)
        ds.PatientSex = 'F'

        # Inject Error 2: Wrong body part examined (ABDOMEN -> HEAD)
        ds.BodyPartExamined = 'HEAD'

        # Inject Error 3: Clear referring physician name
        ds.ReferringPhysicianName = ''

        try:
            ds.save_as(fpath)
            files_modified += 1
        except Exception as e:
            print(f"Could not save {fpath}: {e}")

# Save original values for verification
original_values["files_modified"] = files_modified
with open("/tmp/urologist_metadata_original.json", "w") as f:
    json.dump(original_values, f)

print(f"Injected errors into {files_modified} DICOM files")
print(f"Original values saved to /tmp/urologist_metadata_original.json")
PYEOF

# ---------------------------------------------------------------
# STEP 3: Remove stale output files
# ---------------------------------------------------------------
rm -f "$EXPORT_DIR"/metadata_audit_report.txt 2>/dev/null || true

# ---------------------------------------------------------------
# STEP 4: Record baseline and timestamp
# ---------------------------------------------------------------
DICOM_COUNT=$(find "$STUDY_DIR" -type f 2>/dev/null | head -500 | wc -l)
echo "$DICOM_COUNT" > /tmp/urologist_metadata_initial_count
date +%s > /tmp/urologist_metadata_start_ts

# ---------------------------------------------------------------
# STEP 5: Launch Weasis with the DICOM data pre-loaded
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

# Pre-position: launch Weasis WITH the DICOM data directory
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
take_screenshot /tmp/urologist_metadata_start_screenshot.png

echo "=== Setup Complete ==="
echo "DICOM data in: $STUDY_DIR"
echo "Report target: $EXPORT_DIR/metadata_audit_report.txt"
