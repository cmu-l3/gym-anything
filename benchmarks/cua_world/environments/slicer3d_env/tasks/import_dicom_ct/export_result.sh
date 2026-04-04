#!/bin/bash
echo "=== Exporting Import DICOM CT Task Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Get patient info from setup
PATIENT_ID=$(cat /tmp/task_patient_id.txt 2>/dev/null || echo "LIDC-IDRI-0001")
DICOM_DIR=$(cat /tmp/task_dicom_dir.txt 2>/dev/null || echo "")
INITIAL_DB_MTIME=$(cat /tmp/task_initial_db_mtime.txt 2>/dev/null || echo "0")
INITIAL_PATIENT_COUNT=$(cat /tmp/task_initial_patient_count.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# ============================================================
# CHECK SLICER STATE
# ============================================================
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# ============================================================
# QUERY SLICER FOR DICOM AND VOLUME STATE
# ============================================================
echo "Querying Slicer state..."

cat > /tmp/export_dicom_state.py << 'PYEOF'
import json
import slicer
import os

result = {
    "dicom_database_connected": False,
    "dicom_database_path": "",
    "patients_in_database": 0,
    "patient_ids": [],
    "studies_count": 0,
    "series_count": 0,
    "lidc_patient_found": False,
    "volumes_loaded": 0,
    "volume_names": [],
    "volume_dimensions": [],
    "ct_volume_detected": False,
    "slice_views_have_content": False,
    "dicom_module_accessed": False,
    "error": None
}

try:
    # Check DICOM database
    db = slicer.dicomDatabase
    if db and db.isOpen:
        result["dicom_database_connected"] = True
        result["dicom_database_path"] = db.databaseFilename
        
        # Get patients
        patients = db.patients()
        result["patients_in_database"] = len(patients)
        
        for patient in patients:
            patient_name = db.nameForPatient(patient)
            patient_id = db.fieldForPatient("PatientID", patient)
            result["patient_ids"].append(patient_id or patient_name or str(patient))
            
            # Check for LIDC patient
            if "LIDC" in str(patient_id) or "LIDC" in str(patient_name):
                result["lidc_patient_found"] = True
            
            # Count studies and series
            studies = db.studiesForPatient(patient)
            result["studies_count"] += len(studies)
            for study in studies:
                series_list = db.seriesForStudy(study)
                result["series_count"] += len(series_list)

    # Check loaded volumes
    volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    if volume_nodes:
        result["volumes_loaded"] = volume_nodes.GetNumberOfItems()
        for i in range(volume_nodes.GetNumberOfItems()):
            node = volume_nodes.GetItemAsObject(i)
            result["volume_names"].append(node.GetName())
            
            # Get volume dimensions
            image_data = node.GetImageData()
            if image_data:
                dims = image_data.GetDimensions()
                result["volume_dimensions"].append(list(dims))
                
                # Check if it's a CT (typically >50 slices, 512x512 or similar)
                if dims[2] > 50 and dims[0] >= 256 and dims[1] >= 256:
                    result["ct_volume_detected"] = True

    # Check if slice views have content
    layout_manager = slicer.app.layoutManager()
    if layout_manager:
        for view_name in ["Red", "Yellow", "Green"]:
            slice_widget = layout_manager.sliceWidget(view_name)
            if slice_widget:
                slice_logic = slice_widget.sliceLogic()
                if slice_logic:
                    composite_node = slice_logic.GetSliceCompositeNode()
                    if composite_node and composite_node.GetBackgroundVolumeID():
                        result["slice_views_have_content"] = True
                        break

    # Check if DICOM module was accessed (by checking module history or current module)
    module_manager = slicer.app.moduleManager()
    if module_manager:
        current_module = slicer.util.selectedModule()
        if current_module and "DICOM" in current_module:
            result["dicom_module_accessed"] = True

except Exception as e:
    result["error"] = str(e)

# Save result
with open("/tmp/slicer_dicom_state.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

if [ "$SLICER_RUNNING" = "true" ]; then
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/export_dicom_state.py" > /tmp/slicer_export.log 2>&1 &
    sleep 12
    pkill -f "export_dicom_state.py" 2>/dev/null || true
fi

# Read Slicer state
SLICER_STATE="{}"
if [ -f /tmp/slicer_dicom_state.json ]; then
    SLICER_STATE=$(cat /tmp/slicer_dicom_state.json)
fi

# ============================================================
# CHECK DICOM DATABASE FILE DIRECTLY
# ============================================================
DB_MODIFIED_DURING_TASK="false"
CURRENT_DB_MTIME="0"
CURRENT_PATIENT_COUNT="0"

# Find DICOM database file
DB_FILE=$(cat /tmp/task_dicom_db_path.txt 2>/dev/null || echo "")
if [ -z "$DB_FILE" ]; then
    # Search for it
    DB_FILE=$(find /home/ga/.local/share/NA-MIC -name "ctkDICOM.sql" 2>/dev/null | head -1)
fi

if [ -f "$DB_FILE" ]; then
    CURRENT_DB_MTIME=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo "0")
    
    if [ "$CURRENT_DB_MTIME" -gt "$INITIAL_DB_MTIME" ] && [ "$CURRENT_DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED_DURING_TASK="true"
    fi
    
    # Query patient count if sqlite3 available
    if command -v sqlite3 &> /dev/null; then
        CURRENT_PATIENT_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM Patients;" 2>/dev/null || echo "0")
        
        # Check if LIDC patient exists
        LIDC_IN_DB=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM Patients WHERE PatientID LIKE '%LIDC%';" 2>/dev/null || echo "0")
    fi
    
    echo "DICOM database: $DB_FILE"
    echo "  Initial mtime: $INITIAL_DB_MTIME"
    echo "  Current mtime: $CURRENT_DB_MTIME"
    echo "  Modified during task: $DB_MODIFIED_DURING_TASK"
    echo "  Initial patients: $INITIAL_PATIENT_COUNT"
    echo "  Current patients: $CURRENT_PATIENT_COUNT"
fi

# ============================================================
# EXTRACT KEY VALUES FROM SLICER STATE
# ============================================================
DICOM_CONNECTED=$(echo "$SLICER_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('dicom_database_connected', False))" 2>/dev/null || echo "false")
PATIENTS_COUNT=$(echo "$SLICER_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('patients_in_database', 0))" 2>/dev/null || echo "0")
LIDC_FOUND=$(echo "$SLICER_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('lidc_patient_found', False))" 2>/dev/null || echo "false")
VOLUMES_LOADED=$(echo "$SLICER_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('volumes_loaded', 0))" 2>/dev/null || echo "0")
CT_DETECTED=$(echo "$SLICER_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('ct_volume_detected', False))" 2>/dev/null || echo "false")
VIEWS_HAVE_CONTENT=$(echo "$SLICER_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('slice_views_have_content', False))" 2>/dev/null || echo "false")
DICOM_MODULE_ACCESSED=$(echo "$SLICER_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('dicom_module_accessed', False))" 2>/dev/null || echo "false")
VOLUME_DIMS=$(echo "$SLICER_STATE" | python3 -c "import json,sys; dims=json.load(sys.stdin).get('volume_dimensions', []); print(dims[0] if dims else [])" 2>/dev/null || echo "[]")

# ============================================================
# CHECK SCREENSHOT
# ============================================================
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB=0
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k /tmp/task_final.png 2>/dev/null | cut -f1 || echo "0")
fi

# ============================================================
# CREATE RESULT JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_sec": $((TASK_END - TASK_START)),
    "patient_id": "$PATIENT_ID",
    "dicom_dir": "$DICOM_DIR",
    "slicer_was_running": $SLICER_RUNNING,
    "dicom_database_connected": $DICOM_CONNECTED,
    "db_modified_during_task": $DB_MODIFIED_DURING_TASK,
    "initial_patient_count": $INITIAL_PATIENT_COUNT,
    "current_patient_count": $CURRENT_PATIENT_COUNT,
    "patients_in_database": $PATIENTS_COUNT,
    "lidc_patient_found": $LIDC_FOUND,
    "volumes_loaded": $VOLUMES_LOADED,
    "volume_dimensions": $VOLUME_DIMS,
    "ct_volume_detected": $CT_DETECTED,
    "slice_views_have_content": $VIEWS_HAVE_CONTENT,
    "dicom_module_accessed": $DICOM_MODULE_ACCESSED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "slicer_state": $SLICER_STATE
}
EOF

# Move to final location
rm -f /tmp/dicom_import_result.json 2>/dev/null || sudo rm -f /tmp/dicom_import_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/dicom_import_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/dicom_import_result.json
chmod 666 /tmp/dicom_import_result.json 2>/dev/null || sudo chmod 666 /tmp/dicom_import_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/dicom_import_result.json
echo ""
echo "=== Export Complete ==="