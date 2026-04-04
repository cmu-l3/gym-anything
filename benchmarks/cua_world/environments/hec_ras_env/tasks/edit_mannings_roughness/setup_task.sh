#!/bin/bash
echo "=== Setting up edit_mannings_roughness task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Find the geometry text file to edit
# The Muncie example uses .x04 as the geometry preprocessor input
GEOM_FILE=""
for f in "$MUNCIE_DIR"/Muncie.x04 "$MUNCIE_DIR"/Muncie.g0* "$MUNCIE_DIR"/*.x0*; do
    if [ -f "$f" ] && file "$f" | grep -qi "text"; then
        GEOM_FILE="$f"
        break
    fi
done

if [ -z "$GEOM_FILE" ]; then
    # Try to find any text file with geometry data
    for f in "$MUNCIE_DIR"/Muncie.*; do
        if [ -f "$f" ] && file "$f" | grep -qi "text"; then
            if grep -qi "mann\|roughness\|n val" "$f" 2>/dev/null; then
                GEOM_FILE="$f"
                break
            fi
        fi
    done
fi

if [ -z "$GEOM_FILE" ]; then
    echo "WARNING: Could not find geometry text file with Manning's n values"
    echo "Available files in Muncie directory:"
    ls -la "$MUNCIE_DIR"/
    # Default to .x04
    GEOM_FILE="$MUNCIE_DIR/Muncie.x04"
fi

echo "Using geometry file: $GEOM_FILE"

# 3. Record original Manning's n value for verification
if [ -f "$GEOM_FILE" ]; then
    echo "File type: $(file "$GEOM_FILE")"
    echo "Looking for Manning's n values..."
    grep -n -i "mann\|roughness\|n val" "$GEOM_FILE" 2>/dev/null | head -20 || echo "  (no Manning's n pattern found)"
fi

# 4. Open the geometry file in gedit
echo "Opening geometry file in text editor..."
launch_gedit "$GEOM_FILE"

# 5. Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "The geometry file is now open in the text editor."
echo "Task: Change the main channel Manning's n to 0.05 and save the file."
