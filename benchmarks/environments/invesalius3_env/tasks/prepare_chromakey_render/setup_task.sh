#!/bin/bash
set -e
echo "=== Setting up prepare_chromakey_render task ==="

source /workspace/scripts/task_utils.sh

# Configuration
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
OUTPUT_FILE="$OUTPUT_DIR/chroma_skull.png"

# Ensure output directory exists and is clean
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"
rm -f "$OUTPUT_FILE"

# Ensure data is present
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# 1. Clean up previous instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# 2. Launch InVesalius with data
# We use the launcher wrapper to handle flatpak vs apt differences
echo "Launching InVesalius with data..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_launch.log 2>&1 &"

# 3. Wait for application window
if ! wait_for_invesalius 120; then
    echo "InVesalius failed to launch."
    take_screenshot /tmp/setup_fail.png
    exit 1
fi
sleep 5

# 4. Handle startup dialogs and window management
dismiss_startup_dialogs
focus_invesalius

# Maximize window for best visibility
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz
fi

# 5. Record initial state
date +%s > /tmp/task_start_timestamp
take_screenshot /tmp/task_initial.png

echo "Setup complete. Output expected at: $OUTPUT_FILE"