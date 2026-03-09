#!/bin/bash
# Shared utilities for all Weasis tasks

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Wait for Weasis window to appear
wait_for_weasis() {
    local timeout=${1:-60}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l | grep -qi "weasis"; then
            echo "Weasis window detected"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "Weasis window timeout"
    return 1
}

# Dismiss first-run dialog if it appears
dismiss_first_run_dialog() {
    # Check if first-run dialog appeared
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "First Time"; then
        echo "First-run dialog detected, dismissing..."

        # Focus the dialog window
        DISPLAY=:1 wmctrl -a "First Time" 2>/dev/null || true
        sleep 1

        # Click Accept button - try multiple positions
        for y in 385 390 395; do
            for x in 720 725 730; do
                DISPLAY=:1 xdotool mousemove $x $y click 1 2>/dev/null || true
                sleep 0.3
            done
        done

        # Also try Tab + Enter as fallback
        DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
        sleep 1

        # Check if dialog was dismissed
        if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "First Time"; then
            echo "First-run dialog dismissed"
            return 0
        fi
    fi
    return 0
}

# Get Weasis window ID
get_weasis_window_id() {
    DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1 | awk '{print $1}'
}

# Focus Weasis window
focus_weasis() {
    local win_id=$(get_weasis_window_id)
    if [ -n "$win_id" ]; then
        DISPLAY=:1 wmctrl -i -a "$win_id"
        sleep 0.5
        return 0
    fi
    return 1
}

# Check if Weasis is running
is_weasis_running() {
    pgrep -f "weasis" > /dev/null 2>&1
}

# Launch Weasis if not running
ensure_weasis_running() {
    if ! is_weasis_running; then
        echo "Starting Weasis..."
        DISPLAY=:1 /snap/bin/weasis > /tmp/weasis_ga.log 2>&1 &
        sleep 5
        wait_for_weasis 60
    fi
}

# Launch Weasis with a DICOM file
launch_weasis_with_dicom() {
    local dicom_path="$1"
    echo "Launching Weasis with: $dicom_path"
    DISPLAY=:1 /snap/bin/weasis "$dicom_path" > /tmp/weasis_ga.log 2>&1 &
    sleep 5
    wait_for_weasis 60
}

# Get list of DICOM files in a directory
list_dicom_files() {
    local dir="${1:-/home/ga/DICOM/samples}"
    find "$dir" -type f \( -name "*.dcm" -o -name "*.DCM" -o -name "*.dicom" \) 2>/dev/null
}

# Get first DICOM file in samples directory
get_sample_dicom() {
    list_dicom_files "/home/ga/DICOM/samples" | head -1
}

# Parse DICOM metadata using pydicom
get_dicom_metadata() {
    local dicom_path="$1"
    python3 << PYEOF
import json
try:
    import pydicom
    ds = pydicom.dcmread("$dicom_path")
    metadata = {
        "patient_name": str(ds.PatientName) if hasattr(ds, 'PatientName') else None,
        "patient_id": str(ds.PatientID) if hasattr(ds, 'PatientID') else None,
        "modality": str(ds.Modality) if hasattr(ds, 'Modality') else None,
        "study_description": str(ds.StudyDescription) if hasattr(ds, 'StudyDescription') else None,
        "series_description": str(ds.SeriesDescription) if hasattr(ds, 'SeriesDescription') else None,
        "rows": int(ds.Rows) if hasattr(ds, 'Rows') else None,
        "columns": int(ds.Columns) if hasattr(ds, 'Columns') else None,
        "window_center": float(ds.WindowCenter) if hasattr(ds, 'WindowCenter') else None,
        "window_width": float(ds.WindowWidth) if hasattr(ds, 'WindowWidth') else None,
    }
    print(json.dumps(metadata))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
}

# Check if a DICOM file is loaded in Weasis (based on window title)
check_dicom_loaded() {
    local expected_name="$1"
    local window_title=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1)
    if echo "$window_title" | grep -qi "$expected_name"; then
        return 0
    fi
    return 1
}

# Export verification result to JSON
export_result_json() {
    local output_file="${1:-/tmp/task_result.json}"
    local found="${2:-false}"
    local data="${3:-}"
    local extra="${4:-}"

    # Create JSON in temp file first (permission-safe pattern)
    local temp_json=$(mktemp /tmp/result.XXXXXX.json)

    cat > "$temp_json" << EOF
{
    "found": $found,
    "data": "$data",
    "extra": "$extra",
    "timestamp": "$(date -Iseconds)"
}
EOF

    # Move to final location with permission handling
    rm -f "$output_file" 2>/dev/null || sudo rm -f "$output_file" 2>/dev/null || true
    cp "$temp_json" "$output_file" 2>/dev/null || sudo cp "$temp_json" "$output_file"
    chmod 666 "$output_file" 2>/dev/null || sudo chmod 666 "$output_file" 2>/dev/null || true
    rm -f "$temp_json"

    echo "Result saved to $output_file"
    cat "$output_file"
}
