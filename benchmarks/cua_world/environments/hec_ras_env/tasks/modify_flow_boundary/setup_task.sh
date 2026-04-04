#!/bin/bash
echo "=== Setting up modify_flow_boundary task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Find the boundary conditions file
BC_FILE=""
for f in "$MUNCIE_DIR"/Muncie.b04 "$MUNCIE_DIR"/Muncie.b0* "$MUNCIE_DIR"/Muncie.u0*; do
    if [ -f "$f" ] && file "$f" | grep -qi "text"; then
        BC_FILE="$f"
        break
    fi
done

if [ -z "$BC_FILE" ]; then
    # Search all text files for boundary condition data
    for f in "$MUNCIE_DIR"/Muncie.*; do
        if [ -f "$f" ] && file "$f" | grep -qi "text"; then
            if grep -qi "boundary\|hydrograph\|flow\|discharge" "$f" 2>/dev/null; then
                BC_FILE="$f"
                break
            fi
        fi
    done
fi

if [ -z "$BC_FILE" ]; then
    echo "WARNING: Could not find boundary conditions text file"
    echo "Available files in Muncie directory:"
    ls -la "$MUNCIE_DIR"/
    BC_FILE="$MUNCIE_DIR/Muncie.b04"
fi

echo "Using boundary conditions file: $BC_FILE"

# 3. Record original content for verification
if [ -f "$BC_FILE" ]; then
    echo "File type: $(file "$BC_FILE")"
    cp "$BC_FILE" /tmp/original_boundary_file.bak
    echo "First 30 lines:"
    head -30 "$BC_FILE"
    echo ""
    echo "Looking for flow/hydrograph data:"
    grep -n -i "flow\|discharge\|hydrograph\|boundary" "$BC_FILE" 2>/dev/null | head -20 || echo "  (no patterns found)"
fi

# 4. Open the boundary conditions file in gedit
echo "Opening boundary conditions file in text editor..."
launch_gedit "$BC_FILE"

# 5. Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "The boundary conditions file is now open in the text editor."
echo "Task: Increase the peak flow value by 20% and save the file."
