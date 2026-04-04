#!/bin/bash
# Setup script for surface_mesh_optimization task

set -e
echo "=== Setting up surface_mesh_optimization task ==="

source /workspace/scripts/task_utils.sh

SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
OUTPUT_PLY="$OUTPUT_DIR/skull_optimized.ply"
OUTPUT_STL="$OUTPUT_DIR/skull_optimized.stl"
OUTPUT_PROJECT="$OUTPUT_DIR/mesh_optimization.inv3"

# Ensure output directory exists (owned by ga)
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR" 2>/dev/null || true

# Remove any pre-existing output files to prevent false positives
rm -f "$OUTPUT_PLY" "$OUTPUT_STL" "$OUTPUT_PROJECT"

# Create a 3D printer specification document to differentiate this task's starting state
cat > "$OUTPUT_DIR/3d_print_specs.txt" << 'SPECS'
3D PRINTING SPECIFICATIONS — SKULL MODEL
=========================================
Printer: Formlabs Form 3B (Biocompatible Resin)
Build Volume: 145 x 145 x 185 mm
Layer Thickness: 0.05 mm

File Requirements:
  Format: Binary STL or PLY (ASCII or binary)
  Maximum triangle count: 500,000 triangles
  Maximum file size: 50 MB

Pre-Processing Requirements (MANDATORY):
  1. Apply mesh smoothing (minimum 15 iterations) to remove CT acquisition noise
  2. Apply mesh decimation to achieve triangle count < 500,000

Output Files:
  PLY format:  /home/ga/Documents/skull_optimized.ply
  STL format:  /home/ga/Documents/skull_optimized.stl
  Project:     /home/ga/Documents/mesh_optimization.inv3
SPECS

chown ga:ga "$OUTPUT_DIR/3d_print_specs.txt" 2>/dev/null || true

if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Record baseline state
echo "false" > /tmp/optimization_ply_exists_initial
echo "false" > /tmp/optimization_stl_exists_initial
date +%s > /tmp/task_start_timestamp

# Close any existing InVesalius instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow X automation
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with CT Cranium pre-loaded
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for window and settle
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    tail -n 50 /tmp/invesalius_ga.log 2>/dev/null || true
    exit 1
fi
sleep 3

dismiss_startup_dialogs
focus_invesalius || true

WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

sleep 2
take_screenshot /tmp/task_start.png

echo "Output directory: $OUTPUT_DIR"
echo "3D print specs: $OUTPUT_DIR/3d_print_specs.txt"
echo "Expected PLY: $OUTPUT_PLY"
echo "Expected STL: $OUTPUT_STL"
echo "Expected project: $OUTPUT_PROJECT"
echo "DICOM import dir: $IMPORT_DIR"
echo "=== Setup Complete ==="
