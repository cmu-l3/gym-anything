#!/bin/bash
# Setup script for chinook_blob_management task

echo "=== Setting up Chinook BLOB Management Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Database path
DB_PATH="/home/ga/Documents/databases/chinook.db"
SOURCE_IMAGE="/usr/share/dbeaver-ce/dbeaver.png"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown ga:ga "$EXPORT_DIR" "$SCRIPTS_DIR"

# Clean up any previous attempts
rm -f "$EXPORT_DIR/verified_badge.png"
rm -f "$SCRIPTS_DIR/badge_schema.sql"

# Verify source image exists
if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "WARNING: Source image not found at $SOURCE_IMAGE"
    # Create a dummy image if missing (shouldn't happen in this env, but safe fallback)
    convert -size 100x100 xc:blue "$SOURCE_IMAGE" 2>/dev/null || \
    echo "Dummy Image" > "$SOURCE_IMAGE"
fi

# Calculate and save source hash for verification
sha256sum "$SOURCE_IMAGE" | awk '{print $1}' > /tmp/source_image_hash.txt
echo "Source image hash recorded: $(cat /tmp/source_image_hash.txt)"

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver window
focus_dbeaver

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="