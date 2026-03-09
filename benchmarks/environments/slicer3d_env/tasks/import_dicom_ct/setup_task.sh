#!/bin/bash
echo "=== Setting up Import DICOM CT Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
PATIENT_ID="LIDC-IDRI-0001"
DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clean any previous task state
rm -f /tmp/dicom_import_result.json 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# ============================================================
# STEP 1: Prepare LIDC DICOM Data
# ============================================================
echo "Preparing LIDC-IDRI chest CT DICOM data..."
mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

export PATIENT_ID GROUND_TRUTH_DIR LIDC_DIR
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID"

# Get actual patient ID (may differ if original not available)
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
    DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"
fi

echo "Using patient: $PATIENT_ID"
echo "DICOM directory: $DICOM_DIR"

# Verify DICOM directory exists and has files
if [ ! -d "$DICOM_DIR" ]; then
    echo "ERROR: DICOM directory not found at $DICOM_DIR"
    # Try to find any DICOM directory
    FOUND_DICOM=$(find "$LIDC_DIR" -type d -name "DICOM" 2>/dev/null | head -1)
    if [ -n "$FOUND_DICOM" ]; then
        DICOM_DIR="$FOUND_DICOM"
        echo "Found alternative DICOM directory: $DICOM_DIR"
    else
        exit 1
    fi
fi

DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
echo "Found $DICOM_COUNT files in DICOM directory"

if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "ERROR: Too few DICOM files ($DICOM_COUNT) - data may not have downloaded correctly"
    exit 1
fi

# Save DICOM info for verification
echo "$PATIENT_ID" > /tmp/task_patient_id.txt
echo "$DICOM_DIR" > /tmp/task_dicom_dir.txt
echo "$DICOM_COUNT" > /tmp/task_dicom_count.txt

# ============================================================
# STEP 2: Clear Slicer's DICOM Database (ensure clean state)
# ============================================================
echo "Ensuring clean DICOM database state..."

# Slicer stores DICOM database in user config directory
SLICER_CONFIG_DIRS=(
    "/home/ga/.local/share/NA-MIC"
    "/home/ga/.config/NA-MIC"
)

# Record initial DICOM database state
INITIAL_DB_SIZE=0
INITIAL_DB_PATIENT_COUNT=0

for config_dir in "${SLICER_CONFIG_DIRS[@]}"; do
    if [ -d "$config_dir" ]; then
        # Find DICOM database files
        DB_FILE=$(find "$config_dir" -name "ctkDICOM.sql" 2>/dev/null | head -1)
        if [ -f "$DB_FILE" ]; then
            INITIAL_DB_SIZE=$(stat -c %s "$DB_FILE" 2>/dev/null || echo "0")
            # Query patient count if sqlite3 available
            if command -v sqlite3 &> /dev/null; then
                INITIAL_DB_PATIENT_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM Patients;" 2>/dev/null || echo "0")
            fi
            echo "Found existing DICOM database: $DB_FILE (size: $INITIAL_DB_SIZE bytes, patients: $INITIAL_DB_PATIENT_COUNT)"
            
            # Record database location and initial mtime
            echo "$DB_FILE" > /tmp/task_dicom_db_path.txt
            stat -c %Y "$DB_FILE" > /tmp/task_initial_db_mtime.txt 2>/dev/null || echo "0" > /tmp/task_initial_db_mtime.txt
            break
        fi
    fi
done

# Save initial state
echo "$INITIAL_DB_SIZE" > /tmp/task_initial_db_size.txt
echo "$INITIAL_DB_PATIENT_COUNT" > /tmp/task_initial_patient_count.txt

# ============================================================
# STEP 3: Launch 3D Slicer with Empty Scene
# ============================================================
echo "Launching 3D Slicer with empty scene..."

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer without any file argument
echo "Starting Slicer..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for Slicer to initialize..."
wait_for_slicer 120

# Focus and maximize Slicer window
SLICER_WID=$(get_slicer_window_id)
if [ -n "$SLICER_WID" ]; then
    focus_window "$SLICER_WID"
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Slicer window focused and maximized"
else
    echo "Warning: Could not find Slicer window"
fi

# Give Slicer time to fully initialize
sleep 5

# ============================================================
# STEP 4: Verify Initial State (No Data Loaded)
# ============================================================
echo "Verifying initial state..."

# Check that no volumes are loaded
cat > /tmp/check_initial_state.py << 'PYEOF'
import json
import slicer

result = {
    "volumes_loaded": 0,
    "dicom_database_connected": False,
    "initial_scene_nodes": 0
}

# Count volume nodes
volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
result["volumes_loaded"] = volume_nodes.GetNumberOfItems() if volume_nodes else 0

# Check DICOM database
try:
    db = slicer.dicomDatabase
    if db and db.isOpen:
        result["dicom_database_connected"] = True
except Exception as e:
    result["dicom_database_error"] = str(e)

# Count total scene nodes
result["initial_scene_nodes"] = slicer.mrmlScene.GetNumberOfNodes()

with open("/tmp/initial_slicer_state.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Initial state: {result}")
PYEOF

# Run the check script
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/check_initial_state.py" > /tmp/initial_check.log 2>&1 &
sleep 8
pkill -f "check_initial_state.py" 2>/dev/null || true

# Read initial state
if [ -f /tmp/initial_slicer_state.json ]; then
    cat /tmp/initial_slicer_state.json
fi

# ============================================================
# STEP 5: Take Initial Screenshot
# ============================================================
echo "Capturing initial screenshot..."
sleep 2
take_screenshot /tmp/task_initial.png ga

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# ============================================================
# SETUP COMPLETE
# ============================================================
echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "DICOM data location: $DICOM_DIR"
echo "Number of DICOM files: $DICOM_COUNT"
echo "Patient ID: $PATIENT_ID"
echo ""
echo "TASK: Import this DICOM study into Slicer's DICOM database and load it."
echo ""
echo "Steps:"
echo "  1. Go to Modules → DICOM (or press Ctrl+D)"
echo "  2. Click 'Import' and navigate to: $DICOM_DIR"
echo "  3. Wait for indexing to complete"
echo "  4. Select the patient/study/series in the browser"
echo "  5. Click 'Load' to load the CT into the scene"
echo "  6. Verify chest CT is visible in the slice views"
echo ""