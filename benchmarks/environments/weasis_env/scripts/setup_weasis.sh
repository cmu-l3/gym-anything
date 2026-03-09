#!/bin/bash
# set -euo pipefail

echo "=== Setting up Weasis DICOM Viewer configuration ==="

# Set up Weasis for a specific user
setup_user_weasis() {
    local username=$1
    local home_dir=$2

    echo "Setting up Weasis for user: $username"

    # Give recursive full permissions to the user's cache
    sudo chmod -R 777 /home/$username/.cache 2>/dev/null || true

    # Create Weasis config directory
    # Weasis uses ~/.weasis for normal install or ~/snap/weasis/current/.weasis for snap
    sudo -u $username mkdir -p "$home_dir/.weasis"
    sudo -u $username mkdir -p "$home_dir/snap/weasis/current/.weasis" 2>/dev/null || true

    # Create DICOM directories
    sudo -u $username mkdir -p "$home_dir/DICOM"
    sudo -u $username mkdir -p "$home_dir/DICOM/samples"
    sudo -u $username mkdir -p "$home_dir/DICOM/exports"
    sudo -u $username mkdir -p "$home_dir/Desktop"

    # Download sample DICOM files from public sources
    echo "  - Downloading sample DICOM files..."

    # Download sample DICOM from Rubo Medical (small public samples)
    SAMPLE_DIR="$home_dir/DICOM/samples"

    # Download CT scan sample (compressed)
    wget -q "https://www.rubomedical.com/dicom_files/dicom_viewer_0002.zip" -O /tmp/dicom_sample1.zip 2>/dev/null && {
        unzip -q -o /tmp/dicom_sample1.zip -d "$SAMPLE_DIR/ct_scan/" 2>/dev/null || true
        rm -f /tmp/dicom_sample1.zip
        echo "  - Downloaded CT scan sample"
    } || echo "  - Could not download CT scan sample"

    # Download MR scan sample
    wget -q "https://www.rubomedical.com/dicom_files/dicom_viewer_0003.zip" -O /tmp/dicom_sample2.zip 2>/dev/null && {
        unzip -q -o /tmp/dicom_sample2.zip -d "$SAMPLE_DIR/mr_scan/" 2>/dev/null || true
        rm -f /tmp/dicom_sample2.zip
        echo "  - Downloaded MR scan sample"
    } || echo "  - Could not download MR scan sample"

    # If downloads failed, create synthetic DICOM files using pydicom
    if [ ! -d "$SAMPLE_DIR/ct_scan" ] || [ -z "$(ls -A $SAMPLE_DIR/ct_scan 2>/dev/null)" ]; then
        echo "  - Creating synthetic DICOM files..."
        python3 << 'PYEOF'
import os
import numpy as np

try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_sample_dicom(filename, modality="CT", size=256):
        """Create a sample DICOM file with synthetic image data."""
        # Create file meta information
        file_meta = Dataset()
        file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2'  # CT Image Storage
        file_meta.MediaStorageSOPInstanceUID = generate_uid()
        file_meta.TransferSyntaxUID = ExplicitVRLittleEndian

        # Create the FileDataset instance
        ds = FileDataset(filename, {}, file_meta=file_meta, preamble=b"\0" * 128)

        # Set required DICOM attributes
        dt = datetime.datetime.now()
        ds.ContentDate = dt.strftime('%Y%m%d')
        ds.ContentTime = dt.strftime('%H%M%S.%f')
        ds.StudyInstanceUID = generate_uid()
        ds.SeriesInstanceUID = generate_uid()
        ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
        ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
        ds.Modality = modality
        ds.PatientName = "Test^Patient"
        ds.PatientID = "TEST001"
        ds.PatientBirthDate = "19800101"
        ds.PatientSex = "O"
        ds.StudyDescription = f"Sample {modality} Study"
        ds.SeriesDescription = f"Sample {modality} Series"

        # Image-related attributes
        ds.SamplesPerPixel = 1
        ds.PhotometricInterpretation = "MONOCHROME2"
        ds.Rows = size
        ds.Columns = size
        ds.BitsAllocated = 16
        ds.BitsStored = 12
        ds.HighBit = 11
        ds.PixelRepresentation = 0
        ds.RescaleIntercept = -1024
        ds.RescaleSlope = 1
        ds.WindowCenter = 40
        ds.WindowWidth = 400

        # Create synthetic image data (simple gradient with some features)
        image = np.zeros((size, size), dtype=np.uint16)
        # Add gradient
        for i in range(size):
            for j in range(size):
                image[i, j] = int((i + j) * 4000 / (2 * size))
        # Add a circle (simulating a structure)
        center = size // 2
        radius = size // 4
        for i in range(size):
            for j in range(size):
                if (i - center)**2 + (j - center)**2 < radius**2:
                    image[i, j] = 2000

        ds.PixelData = image.tobytes()

        # Save the file
        ds.save_as(filename)
        print(f"Created: {filename}")

    # Create sample directory
    sample_dir = os.path.expanduser("~/DICOM/samples/synthetic")
    os.makedirs(sample_dir, exist_ok=True)

    # Create multiple DICOM files (simulating a series)
    for i in range(5):
        create_sample_dicom(
            os.path.join(sample_dir, f"CT_slice_{i+1:03d}.dcm"),
            modality="CT",
            size=256
        )

    print("Synthetic DICOM files created successfully")

except ImportError as e:
    print(f"pydicom not available: {e}")
except Exception as e:
    print(f"Error creating DICOM files: {e}")
PYEOF
    fi

    # Set proper permissions for DICOM files
    chown -R $username:$username "$home_dir/DICOM"
    chmod -R 755 "$home_dir/DICOM"

    # Create Weasis preferences file (disable first-run wizard)
    WEASIS_PREFS="$home_dir/.weasis/weasis.properties"
    mkdir -p "$(dirname $WEASIS_PREFS)"
    cat > "$WEASIS_PREFS" << 'PREFSEOF'
# Weasis configuration
weasis.confirm.closing=false
weasis.show.startup.tips=false
weasis.portable.dicom.directory=${user.home}/DICOM
weasis.export.dicom=${user.home}/DICOM/exports
PREFSEOF
    chown $username:$username "$WEASIS_PREFS"

    # Create similar config for snap installation
    SNAP_WEASIS_PREFS="$home_dir/snap/weasis/current/.weasis/weasis.properties"
    mkdir -p "$(dirname $SNAP_WEASIS_PREFS)" 2>/dev/null || true
    cp "$WEASIS_PREFS" "$SNAP_WEASIS_PREFS" 2>/dev/null || true
    chown -R $username:$username "$home_dir/snap" 2>/dev/null || true

    # Create desktop shortcut
    cat > "$home_dir/Desktop/Weasis.desktop" << DESKTOPEOF
[Desktop Entry]
Name=Weasis DICOM Viewer
Comment=View DICOM medical images
Exec=/snap/bin/weasis %F
Icon=weasis
StartupNotify=true
Terminal=false
MimeType=application/dicom;
Categories=Graphics;MedicalSoftware;Viewer;
Type=Application
DESKTOPEOF

    # If snap not available, use native weasis
    if ! command -v /snap/bin/weasis &> /dev/null; then
        sed -i 's|/snap/bin/weasis|weasis|g' "$home_dir/Desktop/Weasis.desktop"
    fi

    chown $username:$username "$home_dir/Desktop/Weasis.desktop"
    chmod +x "$home_dir/Desktop/Weasis.desktop"
    echo "  - Created desktop shortcut"

    # Create launch script
    cat > "$home_dir/launch_weasis.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch Weasis with optimized settings
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Determine Weasis executable
if command -v /snap/bin/weasis &> /dev/null; then
    WEASIS_CMD="/snap/bin/weasis"
elif command -v weasis &> /dev/null; then
    WEASIS_CMD="weasis"
else
    echo "Weasis not found!"
    exit 1
fi

# Launch Weasis
$WEASIS_CMD "$@" > /tmp/weasis_$USER.log 2>&1 &

echo "Weasis started"
echo "Log file: /tmp/weasis_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_weasis.sh"
    chmod +x "$home_dir/launch_weasis.sh"
    echo "  - Created launch script"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_weasis "ga" "/home/ga"
fi

# Create utility scripts
cat > /usr/local/bin/dicom-info << 'INFOEOF'
#!/bin/bash
# DICOM file info utility
# Usage: dicom-info <dicom_file>

if [ $# -eq 0 ]; then
    echo "Usage: dicom-info <dicom_file>"
    exit 1
fi

echo "=== DICOM Information ==="
echo "File: $1"
echo ""

# Try dcmdump if available
if command -v dcmdump &> /dev/null; then
    echo "--- DCMTK dcmdump ---"
    dcmdump "$1" 2>/dev/null | head -100
else
    # Fall back to Python pydicom
    python3 << PYEOF
import sys
try:
    import pydicom
    ds = pydicom.dcmread("$1")
    print("Patient Name:", ds.PatientName if hasattr(ds, 'PatientName') else "N/A")
    print("Patient ID:", ds.PatientID if hasattr(ds, 'PatientID') else "N/A")
    print("Modality:", ds.Modality if hasattr(ds, 'Modality') else "N/A")
    print("Study Description:", ds.StudyDescription if hasattr(ds, 'StudyDescription') else "N/A")
    print("Image Size:", f"{ds.Rows}x{ds.Columns}" if hasattr(ds, 'Rows') else "N/A")
except Exception as e:
    print(f"Error: {e}")
PYEOF
fi
INFOEOF
chmod +x /usr/local/bin/dicom-info

echo "=== Weasis DICOM Viewer configuration completed ==="

echo "Weasis is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run '/snap/bin/weasis' from terminal"
echo "  - Run '~/launch_weasis.sh <file>' for optimized launch"
echo "  - Use 'dicom-info <file>' to inspect DICOM files"
echo ""
echo "NOTE: On first launch, Weasis will show a disclaimer dialog."
echo "Click 'Accept' to dismiss it."
