#!/bin/bash
set -e
echo "=== Setting up Binary DICOM Transfer Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Setup Directories
INPUT_DIR="/home/ga/dicom_input"
OUTPUT_DIR="/home/ga/dicom_output"

mkdir -p "$INPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Clean up any previous runs
rm -f "$INPUT_DIR"/*
rm -f "$OUTPUT_DIR"/*
rm -f /tmp/dicom_task_result.json

# 2. Prepare Data (Real DICOM file)
SAMPLE_FILE="$INPUT_DIR/CT_small.dcm"
echo "Preparing DICOM data..."

# Try to download real sample data from pydicom
if curl -L -o "$SAMPLE_FILE" --max-time 10 "https://github.com/pydicom/pydicom/raw/master/pydicom/data/test_files/CT_small.dcm"; then
    echo "Downloaded real DICOM sample."
else
    echo "Download failed. Generating synthetic binary DICOM-like file..."
    # Create a file with binary data that guarantees corruption if treated as UTF-8/ASCII
    # 128 bytes preamble + "DICM" + binary garbage including 0x00, 0xFF, 0x80
    python3 -c 'import sys; sys.stdout.buffer.write(b"\x00"*128 + b"DICM" + bytes(range(256))*10)' > "$SAMPLE_FILE"
fi

# Set permissions
chown -R ga:ga "$INPUT_DIR" "$OUTPUT_DIR"
chmod 644 "$SAMPLE_FILE"

# 3. Record Initial State
INITIAL_MD5=$(md5sum "$SAMPLE_FILE" | cut -d' ' -f1)
echo "$INITIAL_MD5" > /tmp/initial_dicom_md5.txt
date +%s > /tmp/task_start_time.txt

echo "Input File MD5: $INITIAL_MD5"

# 4. Launch Terminal for Agent
# Open a terminal window for the agent to use
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - DICOM Binary Migration"
echo "============================================"
echo ""
echo "TASK: Create a channel to move DICOM files."
echo "      Ensure BINARY integrity is preserved."
echo ""
echo "Input Directory:  /home/ga/dicom_input/"
echo "Output Directory: /home/ga/dicom_output/"
echo "Required Suffix:  _migrated"
echo ""
echo "Web Dashboard: https://localhost:8443"
echo "  Credentials: admin / admin"
echo ""
echo "NOTE: If you configure the channel incorrectly,"
echo "the binary image data will be corrupted."
echo "============================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2

# Focus the terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# 5. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="