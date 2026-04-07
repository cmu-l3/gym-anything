#!/bin/bash
echo "=== Setting up export_srs_book_pdf task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and clean up any previous run artifacts
mkdir -p /home/ga/Documents
OUTPUT_FILE="/home/ga/Documents/SRS_Release_1.0.pdf"
rm -f "$OUTPUT_FILE" 2>/dev/null || true

# Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
PROJECT_PATH=$(setup_task_project "export_pdf_book")
echo "Task project path: $PROJECT_PATH"

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

# Wait for application to stabilize
sleep 5

# Dismiss any startup dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the SRS document so it's ready for the agent
open_srs_document

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="