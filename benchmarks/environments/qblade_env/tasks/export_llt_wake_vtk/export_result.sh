#!/bin/bash
echo "=== Exporting export_llt_wake_vtk result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot (Evidence of GUI state)
take_screenshot /tmp/task_final.png

# 2. Get Task Timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Search for Output Files
PROJECT_DIR="/home/ga/Documents/projects"
VTK_FILE=""
VTK_SIZE=0
VTK_CREATED="false"

# Look for standard VTK extensions exported by QBlade/ParaView
# QBlade often exports .vtu (Unstructured Grid) or .vtr (Rectilinear Grid) or .pvd (Collection)
FOUND_VTK=$(find "$PROJECT_DIR" -maxdepth 1 \( -name "wake_cutplane.vtu" -o -name "wake_cutplane.vtr" -o -name "wake_cutplane.vtk" -o -name "wake_cutplane.pvd" \) -print -quit)

if [ -n "$FOUND_VTK" ]; then
    VTK_FILE="$FOUND_VTK"
    VTK_SIZE=$(stat -c%s "$VTK_FILE" 2>/dev/null || echo "0")
    
    # Check creation time against task start
    FILE_MTIME=$(stat -c%Y "$VTK_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        VTK_CREATED="true"
    fi
fi

# 4. Check Project File
WPA_FILE="$PROJECT_DIR/llt_simulation.wpa"
WPA_EXISTS="false"
WPA_CREATED="false"

if [ -f "$WPA_FILE" ]; then
    WPA_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$WPA_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        WPA_CREATED="true"
    fi
fi

# 5. Check if QBlade is still running
APP_RUNNING=$(is_qblade_running)

# 6. Create Result JSON
# We include the first few lines of the VTK file to verify it's not a dummy text file
VTK_HEADER=""
if [ -f "$VTK_FILE" ]; then
    VTK_HEADER=$(head -n 5 "$VTK_FILE" | tr -d '\000-\011\013-\037') # Clean control chars
fi

write_result_json "$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "vtk_file_path": "$VTK_FILE",
    "vtk_file_exists": $([ -n "$VTK_FILE" ] && echo "true" || echo "false"),
    "vtk_created_during_task": $VTK_CREATED,
    "vtk_file_size": $VTK_SIZE,
    "vtk_header_snippet": "$VTK_HEADER",
    "project_file_exists": $WPA_EXISTS,
    "project_created_during_task": $WPA_CREATED,
    "app_was_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false")
}
EOF
)"

echo "=== Export complete ==="