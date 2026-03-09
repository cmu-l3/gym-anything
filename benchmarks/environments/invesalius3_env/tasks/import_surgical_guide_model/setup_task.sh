#!/bin/bash
set -e
echo "=== Setting up Import Surgical Guide Task ==="

source /workspace/scripts/task_utils.sh

# 1. Define paths
DOCS_DIR="/home/ga/Documents"
GUIDE_STL="$DOCS_DIR/surgical_guide.stl"
SERIES_DIR="/home/ga/DICOM/ct_cranium"

# 2. Prepare directories and clean state
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"
rm -f "$DOCS_DIR/guide_verification.inv3" 2>/dev/null

# 3. Generate the Synthetic Surgical Guide STL
# Creating a simple geometric shape (a small block) positioned to intersect 
# where the skull usually is in this dataset (approx 250, 250, 50 in volume coords).
echo "Generating surgical guide STL..."
cat > "$GUIDE_STL" <<EOF
solid surgical_guide
facet normal 0 0 -1
outer loop
vertex 250 250 50
vertex 290 250 50
vertex 270 290 50
endloop
endfacet
facet normal 0 0 1
outer loop
vertex 250 250 50
vertex 290 250 50
vertex 270 270 90
endloop
endfacet
facet normal 0 -1 0
outer loop
vertex 250 250 50
vertex 270 290 50
vertex 270 270 90
endloop
endfacet
facet normal 1 0 0
outer loop
vertex 290 250 50
vertex 270 290 50
vertex 270 270 90
endloop
endfacet
endsolid surgical_guide
EOF
chown ga:ga "$GUIDE_STL"

# 4. Ensure InVesalius is not running
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# 5. Check DICOM data
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# 6. Launch InVesalius with data loaded
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# 7. Wait for window
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    exit 1
fi
sleep 5

# 8. Handle dialogs and focus
dismiss_startup_dialogs
focus_invesalius || true
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# 9. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Guide STL created at: $GUIDE_STL"