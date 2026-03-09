#!/bin/bash
echo "=== Setting up Adjust Lung Window Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
PATIENT_ID="LIDC-IDRI-0001"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# ============================================================
# Prepare LIDC data
# ============================================================
echo "Preparing LIDC-IDRI chest CT data..."
mkdir -p "$LIDC_DIR"

export PATIENT_ID LIDC_DIR
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID" || {
    echo "WARNING: LIDC data preparation had issues, continuing..."
}

# Get the actual patient ID used (may differ if requested one wasn't available)
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"

echo "Using patient: $PATIENT_ID"
echo "DICOM directory: $DICOM_DIR"

# Verify DICOM data exists
if [ ! -d "$DICOM_DIR" ]; then
    echo "ERROR: DICOM directory not found at $DICOM_DIR"
    # Try to find any DICOM data
    DICOM_DIR=$(find "$LIDC_DIR" -type d -name "DICOM" 2>/dev/null | head -1)
    if [ -z "$DICOM_DIR" ]; then
        echo "ERROR: No DICOM data found"
        exit 1
    fi
    echo "Found DICOM at: $DICOM_DIR"
fi

DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
echo "Found $DICOM_COUNT DICOM files"

if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "WARNING: Few DICOM files found ($DICOM_COUNT)"
fi

# ============================================================
# Record initial W/L state for verification
# ============================================================
INITIAL_WINDOW=400
INITIAL_LEVEL=40

cat > /tmp/initial_wl_state.json << EOF
{
    "initial_window": $INITIAL_WINDOW,
    "initial_level": $INITIAL_LEVEL,
    "task_start_time": $(date +%s),
    "patient_id": "$PATIENT_ID",
    "dicom_dir": "$DICOM_DIR",
    "dicom_count": $DICOM_COUNT
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_wl_state.json

# ============================================================
# Clean any previous results
# ============================================================
rm -f /tmp/lung_window_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# ============================================================
# Launch 3D Slicer and load DICOM data
# ============================================================
echo "Launching 3D Slicer..."

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Python script to load DICOM and set initial W/L
cat > /tmp/load_lidc_and_set_wl.py << 'PYEOF'
import slicer
import os
import time

dicom_dir = os.environ.get("DICOM_DIR", "/home/ga/Documents/SlicerData/LIDC/LIDC-IDRI-0001/DICOM")
initial_window = 400
initial_level = 40

print(f"Loading DICOM from: {dicom_dir}")

# Import DICOM
try:
    from DICOMLib import DICOMUtils
    
    # Add DICOM directory to database
    indexer = ctk.ctkDICOMIndexer()
    indexer.addDirectory(slicer.dicomDatabase, dicom_dir)
    
    # Get patient/study info
    patients = slicer.dicomDatabase.patients()
    if patients:
        patient = patients[0]
        studies = slicer.dicomDatabase.studiesForPatient(patient)
        if studies:
            study = studies[0]
            series_list = slicer.dicomDatabase.seriesForStudy(study)
            if series_list:
                # Load the first (or largest) series
                largest_series = None
                max_files = 0
                for series in series_list:
                    files = slicer.dicomDatabase.filesForSeries(series)
                    if len(files) > max_files:
                        max_files = len(files)
                        largest_series = series
                
                if largest_series:
                    print(f"Loading series with {max_files} files")
                    DICOMUtils.loadSeriesByUID([largest_series])
                    print("DICOM loaded successfully")

except Exception as e:
    print(f"DICOM import method failed: {e}")
    print("Trying alternative method...")
    
    # Alternative: use Add Data dialog approach via Python
    try:
        # Get list of DICOM files
        import glob
        dcm_files = glob.glob(os.path.join(dicom_dir, "*"))
        if dcm_files:
            # Try loading first file which should trigger series loading
            slicer.util.loadVolume(dcm_files[0])
            print("Loaded via loadVolume")
    except Exception as e2:
        print(f"Alternative loading failed: {e2}")

# Wait for volume to appear
time.sleep(2)

# Set initial window/level to soft tissue window
volumes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
print(f"Found {len(volumes)} volume(s)")

for vol in volumes:
    display_node = vol.GetDisplayNode()
    if display_node:
        print(f"Setting W/L for volume: {vol.GetName()}")
        display_node.AutoWindowLevelOff()
        display_node.SetWindow(initial_window)
        display_node.SetLevel(initial_level)
        print(f"Set Window={initial_window}, Level={initial_level}")
        
        # Verify
        actual_w = display_node.GetWindow()
        actual_l = display_node.GetLevel()
        print(f"Verified: Window={actual_w}, Level={actual_l}")

# Switch to conventional layout
lm = slicer.app.layoutManager()
lm.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)

# Reset slice views to show the data
slicer.util.resetSliceViews()

print("Setup complete - soft tissue window applied")
PYEOF

# Export environment variable for the Python script
export DICOM_DIR

# Launch Slicer
echo "Starting 3D Slicer with DICOM data..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for Slicer to start..."
wait_for_slicer 90

# Give Slicer time to fully initialize
sleep 5

# Run the setup script inside Slicer
echo "Loading DICOM data and setting initial window/level..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash --python-script /tmp/load_lidc_and_set_wl.py" &
SLICER_SETUP_PID=$!

# Wait for setup script to complete (with timeout)
for i in {1..60}; do
    if ! ps -p $SLICER_SETUP_PID > /dev/null 2>&1; then
        echo "Setup script completed"
        break
    fi
    sleep 2
done

# Kill setup process if still running
kill $SLICER_SETUP_PID 2>/dev/null || true

# Wait a bit more for Slicer to stabilize
sleep 3

# Restart Slicer fresh with the data loaded
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer fresh - it should remember the DICOM database
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_main.log 2>&1 &"
wait_for_slicer 60

# Apply initial W/L again after fresh start
sleep 5
cat > /tmp/set_initial_wl.py << 'PYEOF'
import slicer
import time

# Wait for any volume to load
time.sleep(3)

volumes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
print(f"Found {len(volumes)} volumes")

if not volumes:
    # Try loading from DICOM browser
    print("No volumes, attempting DICOM load...")
    try:
        mainWindow = slicer.util.mainWindow()
        mainWindow.moduleSelector().selectModule("DICOM")
    except:
        pass

# Set soft tissue window
for vol in volumes:
    display_node = vol.GetDisplayNode()
    if display_node:
        display_node.AutoWindowLevelOff()
        display_node.SetWindow(400)
        display_node.SetLevel(40)
        print(f"Set {vol.GetName()} to W=400, L=40")

# Go to Axial view
lm = slicer.app.layoutManager()
lm.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)
slicer.util.resetSliceViews()
PYEOF

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/set_initial_wl.py --no-main-window" &
sleep 10
pkill -f "set_initial_wl" 2>/dev/null || true

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Adjust the CT window/level from soft tissue to lung window"
echo ""
echo "Current settings (soft tissue window):"
echo "  Window: 400 HU"
echo "  Level: 40 HU"
echo ""
echo "Target settings (lung window):"
echo "  Window: ~1500 HU (acceptable: 1200-1800)"
echo "  Level: ~-600 HU (acceptable: -700 to -500)"
echo ""
echo "Use the Volumes module Display section to adjust Window/Level."
echo "After adjustment, lung parenchyma should appear dark/gray with visible structures."