#!/bin/bash
set -e
echo "=== Setting up Probit Labor Participation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
rm -rf /home/ga/Documents/gretl_output
mkdir -p /home/ga/Documents/gretl_output
chown -R ga:ga /home/ga/Documents/gretl_output

# Define dataset path
MROZ_PATH="/home/ga/Documents/gretl_data/mroz.gdt"
POE5_SRC="/opt/gretl_data/poe5/mroz.gdt"

# Ensure mroz.gdt is present
if [ ! -f "$MROZ_PATH" ]; then
    echo "mroz.gdt not found in Documents, checking source..."
    if [ -f "$POE5_SRC" ]; then
        echo "Copying mroz.gdt from POE5 data..."
        cp "$POE5_SRC" "$MROZ_PATH"
        chown ga:ga "$MROZ_PATH"
    else
        echo "Trying system data locations..."
        FOUND=false
        for d in /usr/share/gretl/data /usr/share/gretl/data/misc /usr/share/gretl/data/poe5 /usr/share/gretl/data/wooldridge; do
            if [ -f "$d/mroz.gdt" ]; then
                cp "$d/mroz.gdt" "$MROZ_PATH"
                chown ga:ga "$MROZ_PATH"
                FOUND=true
                break
            fi
        done
        
        if [ "$FOUND" = "false" ]; then
             echo "ERROR: mroz.gdt not found. This task requires the Mroz dataset."
             # Fallback creation of minimal dataset would go here in production
             exit 1
        fi
    fi
fi

echo "Dataset confirmed at $MROZ_PATH"

# Standard task setup: kill gretl, launch with dataset
# This utilizes the shared utility which handles window focusing, maximizing, etc.
setup_gretl_task "mroz.gdt" "probit_task"

echo "=== Setup complete ==="