#!/usr/bin/env bash
set -e

# ─── Source shared utilities ────────────────────────────────────────────────
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    # Minimal fallback stubs
    take_screenshot() { DISPLAY=:1 import -window root "$1" 2>/dev/null || DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
    wait_for_weasis() {
        local timeout=${1:-60}
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "weasis"; then return 0; fi
            sleep 2; elapsed=$((elapsed + 2))
        done
        return 1
    }
    dismiss_first_run_dialog() {
        sleep 2
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 1
    }
fi

# ─── Configuration ──────────────────────────────────────────────────────────
EXPORT_DIR="/home/ga/DICOM/exports/tissue_char"
DATA_DIR="/home/ga/DICOM/studies/tissue_phantom"
RESULT_PREFIX="tissue_char"

# ─── Clean stale outputs BEFORE recording timestamp ─────────────────────────
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/density_analysis.png"
rm -f "$EXPORT_DIR/density_analysis.jpg"
rm -f "$EXPORT_DIR/density_analysis.jpeg"
rm -f "$EXPORT_DIR/density_report.txt"
chown -R ga:ga "$EXPORT_DIR" 2>/dev/null || true

# ─── Record anti-gaming timestamp ──────────────────────────────────────────
date +%s > /tmp/${RESULT_PREFIX}_start_ts
chmod 666 /tmp/${RESULT_PREFIX}_start_ts

# ─── Generate 40-slice synthetic CT phantom via pydicom ────────────────────
mkdir -p "$DATA_DIR"
rm -rf "$DATA_DIR"/*

python3 << 'PYEOF'
import numpy as np
import os
import math

try:
    import pydicom
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid
except ImportError:
    import subprocess
    subprocess.check_call(["pip3", "install", "pydicom"])
    import pydicom
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid

out_dir = "/home/ga/DICOM/studies/tissue_phantom"
os.makedirs(out_dir, exist_ok=True)

# ── UIDs (shared across all slices) ──
study_uid = generate_uid()
series_uid = generate_uid()
frame_of_ref_uid = generate_uid()

# ── Constants ──
NUM_SLICES = 40
ROWS = 512
COLS = 512
PIXEL_SPACING = 0.68          # mm per pixel
SLICE_THICKNESS = 3.0         # mm
RESCALE_INTERCEPT = -1024
RESCALE_SLOPE = 1

def hu_to_stored(hu):
    """Convert Hounsfield Units to stored pixel value."""
    return int(hu - RESCALE_INTERCEPT)

for s in range(NUM_SLICES):
    # Reproducible noise per slice
    rng = np.random.RandomState(42 + s)

    # Base: air background (HU = -1024 -> stored = 0)
    pixels = np.zeros((ROWS, COLS), dtype=np.int16)

    # Coordinate grids (row=y, col=x)
    yy, xx = np.mgrid[0:ROWS, 0:COLS]

    # ── 1. Body Contour ──
    # Ellipse centered at (256,256), semi-major=215px, semi-minor=155px
    # HU = 0 (water/muscle baseline)
    body_mask = ((xx - 256)**2 / 215.0**2 + (yy - 256)**2 / 155.0**2) <= 1.0
    pixels[body_mask] = hu_to_stored(0)

    # ── 2. Left Lung ──
    # Ellipse at (155, 240), semi-a=78, semi-b=95, HU = -850
    ll_mask = ((xx - 155)**2 / 78.0**2 + (yy - 240)**2 / 95.0**2) <= 1.0
    pixels[ll_mask] = hu_to_stored(-850)

    # ── 3. Right Lung ──
    # Ellipse at (357, 240), semi-a=78, semi-b=95, HU = -850
    rl_mask = ((xx - 357)**2 / 78.0**2 + (yy - 240)**2 / 95.0**2) <= 1.0
    pixels[rl_mask] = hu_to_stored(-850)

    # ── 4. Central Cardiac Structure (measurement + ROI target) ──
    # Gaussian size profile peaking at slice 16
    cardiac_semi_x = 22.0 + 40.0 * math.exp(-0.5 * ((s - 16) / 7.0)**2)
    cardiac_semi_y = 18.0 + 30.0 * math.exp(-0.5 * ((s - 16) / 7.0)**2)
    cardiac_mask = ((xx - 235)**2 / cardiac_semi_x**2 + (yy - 250)**2 / cardiac_semi_y**2) <= 1.0
    pixels[cardiac_mask] = hu_to_stored(55)

    # ── 5. Vertebral Body (bone ROI target) ──
    # Circle at (256, 375), radius=17, HU = 280
    vert_mask = ((xx - 256)**2 + (yy - 375)**2) <= 17.0**2
    pixels[vert_mask] = hu_to_stored(280)

    # ── 6. Descending Aorta ──
    # Circle at (288, 328), radius=11, HU = 45
    aorta_mask = ((xx - 288)**2 + (yy - 328)**2) <= 11.0**2
    pixels[aorta_mask] = hu_to_stored(45)

    # ── Add Gaussian noise (sigma=8 HU) for realism ──
    noise = rng.normal(0, 8, (ROWS, COLS)).astype(np.int16)
    pixels = pixels + noise

    # ── Create DICOM dataset ──
    filename = os.path.join(out_dir, "slice_{:03d}.dcm".format(s))

    file_meta = pydicom.Dataset()
    file_meta.MediaStorageSOPClassUID = "1.2.840.10008.5.1.4.1.1.2"   # CT Image Storage
    file_meta.MediaStorageSOPInstanceUID = generate_uid()
    file_meta.TransferSyntaxUID = "1.2.840.10008.1.2.1"               # Explicit VR Little Endian

    ds = FileDataset(filename, {}, file_meta=file_meta, preamble=b"\x00" * 128)

    # Patient
    ds.PatientName = "QAPhantom^Chest"
    ds.PatientID = "QA-TISSUE-001"
    ds.PatientSex = "O"
    ds.PatientBirthDate = ""

    # Study
    ds.StudyInstanceUID = study_uid
    ds.StudyDate = "20260101"
    ds.StudyTime = "120000"
    ds.StudyDescription = "Chest QA Phantom"
    ds.AccessionNumber = "QA001"
    ds.ReferringPhysicianName = "QA^Lab"
    ds.InstitutionName = "QA Lab"

    # Series
    ds.SeriesInstanceUID = series_uid
    ds.SeriesNumber = 1
    ds.SeriesDescription = "Axial Chest"
    ds.Modality = "CT"
    ds.BodyPartExamined = "CHEST"

    # Instance
    ds.SOPClassUID = "1.2.840.10008.5.1.4.1.1.2"
    ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
    ds.InstanceNumber = s + 1

    # Frame of Reference
    ds.FrameOfReferenceUID = frame_of_ref_uid
    ds.PositionReferenceIndicator = ""

    # Image Pixel Module
    ds.Rows = ROWS
    ds.Columns = COLS
    ds.BitsAllocated = 16
    ds.BitsStored = 16
    ds.HighBit = 15
    ds.PixelRepresentation = 1      # Signed
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"

    # CT-specific
    ds.RescaleIntercept = str(RESCALE_INTERCEPT)
    ds.RescaleSlope = str(RESCALE_SLOPE)
    ds.WindowCenter = "40"
    ds.WindowWidth = "400"
    ds.PixelSpacing = [str(PIXEL_SPACING), str(PIXEL_SPACING)]
    ds.SliceThickness = str(SLICE_THICKNESS)
    ds.ImagePositionPatient = ["0", "0", str(round(s * SLICE_THICKNESS, 1))]
    ds.ImageOrientationPatient = ["1", "0", "0", "0", "1", "0"]
    ds.SliceLocation = str(round(s * SLICE_THICKNESS, 1))

    ds.PixelData = pixels.tobytes()
    ds.save_as(filename)

print("Generated {} DICOM slices in {}".format(NUM_SLICES, out_dir))
PYEOF

chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

echo "Phantom generation complete. Files:"
ls -la "$DATA_DIR/" | head -5
echo "... ($(ls "$DATA_DIR/" | wc -l) total files)"

# ─── Kill any existing Weasis process ──────────────────────────────────────
pkill -f weasis 2>/dev/null || true
sleep 3

# ─── Launch Weasis with phantom data pre-loaded ───────────────────────────
WEASIS_CMD=""
if command -v /snap/bin/weasis &>/dev/null; then
    WEASIS_CMD="/snap/bin/weasis"
elif command -v weasis &>/dev/null; then
    WEASIS_CMD="weasis"
else
    WEASIS_CMD="/snap/bin/weasis"
fi

su - ga -c "DISPLAY=:1 $WEASIS_CMD '$DATA_DIR' > /tmp/weasis_tissue_char.log 2>&1 &"
sleep 5

# ─── Wait for Weasis window ───────────────────────────────────────────────
echo "Waiting for Weasis window..."
wait_for_weasis 60 || {
    echo "WARNING: Weasis window not detected after 60s, continuing anyway"
}

# ─── Dismiss first-run dialog ─────────────────────────────────────────────
dismiss_first_run_dialog
sleep 2

# ─── Maximize window ─────────────────────────────────────────────────────
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# ─── Focus the Weasis window ─────────────────────────────────────────────
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true
sleep 1

# ─── Take initial screenshot ─────────────────────────────────────────────
take_screenshot /tmp/${RESULT_PREFIX}_start.png

echo "=== tissue_density_characterization setup complete ==="
