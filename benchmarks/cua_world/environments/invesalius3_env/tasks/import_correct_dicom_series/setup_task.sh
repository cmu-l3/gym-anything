#!/bin/bash
set -e
echo "=== Setting up import_correct_dicom_series task ==="

source /workspace/scripts/task_utils.sh

# Configuration
SOURCE_DICOM="/home/ga/DICOM/ct_cranium"
MIXED_DIR="/home/ga/DICOM/mixed_data"
OUTPUT_FILE="/home/ga/Documents/axial_skull.stl"

# Cleanup previous runs
rm -rf "$MIXED_DIR"
rm -f "$OUTPUT_FILE"
mkdir -p "$MIXED_DIR"

# Check source data
if ! ensure_dicom_series_present "$SOURCE_DICOM"; then
    echo "Error: Source DICOM not found at $SOURCE_DICOM"
    exit 1
fi

# ------------------------------------------------------------------
# GENERATE DISTRACTOR DATA
# We need to create a "Scout" series that InVesalius sees as distinct.
# We will use Python (likely available as InVesalius dep) to modify
# tags: SeriesDescription and SeriesInstanceUID.
# ------------------------------------------------------------------

echo "Generating mixed DICOM dataset..."

python3 - <<EOF
import os
import shutil
import glob
import uuid
import sys

# Try to import pydicom (InVesalius dependency) or fall back to manual copy
try:
    import pydicom
    has_pydicom = True
except ImportError:
    print("Warning: pydicom not found. Using simple file copy (may not separate series correctly).")
    has_pydicom = False

source_dir = "$SOURCE_DICOM"
dest_dir = "$MIXED_DIR"
scout_dir = os.path.join(dest_dir, "scout_localizer")
axial_dir = os.path.join(dest_dir, "axial_volumetric")

os.makedirs(scout_dir, exist_ok=True)
os.makedirs(axial_dir, exist_ok=True)

# Get all dicom files
files = sorted(glob.glob(os.path.join(source_dir, "*")))
if not files:
    # Try recursive if flat list empty
    files = sorted(glob.glob(os.path.join(source_dir, "**", "*"), recursive=True))
    files = [f for f in files if os.path.isfile(f)]

# Separate into "Scout" (first 3 slices) and "Axial" (all slices)
# We copy all to Axial, and 3 to Scout, then modify Scout headers
scout_files = files[50:53] if len(files) > 50 else files[:3]
axial_files = files

# 1. Setup Axial Series (Symlink or Copy)
# We just copy them to be safe against permission issues
for f in axial_files:
    shutil.copy(f, axial_dir)

# 2. Setup Scout Series (Modify Headers)
if has_pydicom and scout_files:
    new_series_uid = pydicom.uid.generate_uid()
    for f in scout_files:
        try:
            ds = pydicom.dcmread(f)
            # Modify tags to make it look like a distinct Scout series
            ds.SeriesDescription = "Scout Localizer"
            ds.SeriesInstanceUID = new_series_uid
            ds.SeriesNumber = 99
            
            # Save to scout dir
            basename = os.path.basename(f)
            ds.save_as(os.path.join(scout_dir, "scout_" + basename))
        except Exception as e:
            print(f"Error modifying DICOM {f}: {e}")
else:
    # Fallback if no pydicom: Just copy and hope folders separate them
    # (InVesalius might merge them if UIDs match, but this is best effort)
    for f in scout_files:
        shutil.copy(f, os.path.join(scout_dir, "scout_" + os.path.basename(f)))

print(f"Created Axial series with {len(axial_files)} files")
print(f"Created Scout series with {len(scout_files)} files")
EOF

# Ensure permissions
chown -R ga:ga "$MIXED_DIR"
chmod -R 755 "$MIXED_DIR"

# ------------------------------------------------------------------
# APP SETUP
# ------------------------------------------------------------------

# Close existing instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Start InVesalius (Empty, so agent has to click Import)
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch > /tmp/invesalius_ga.log 2>&1 &"

if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout."
    exit 1
fi
sleep 3

dismiss_startup_dialogs
focus_invesalius || true

# Maximize
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# Timestamps and initial evidence
date +%s > /tmp/task_start_time
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Mixed data prepared at: $MIXED_DIR"