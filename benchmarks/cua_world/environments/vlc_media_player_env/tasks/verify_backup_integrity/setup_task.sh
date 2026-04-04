#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Backup Integrity Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create directory structure
echo "Creating directory structure..."
mkdir -p /home/ga/Videos/original
mkdir -p /home/ga/Videos/backup
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Videos/original
chown -R ga:ga /home/ga/Videos/backup
chown -R ga:ga /home/ga/Documents

# Use existing sample video or create one
SOURCE_VIDEO="/home/ga/Videos/sample_video.mp4"

if [ ! -f "$SOURCE_VIDEO" ]; then
    echo "Sample video not found, will try to use color_test.mp4"
    SOURCE_VIDEO="/home/ga/Videos/color_test.mp4"
fi

if [ ! -f "$SOURCE_VIDEO" ]; then
    echo "ERROR: No source video available for backup integrity test"
    exit 1
fi

# Copy to original location
echo "Creating original video..."
cp "$SOURCE_VIDEO" /home/ga/Videos/original/important_recording.mp4
chown ga:ga /home/ga/Videos/original/important_recording.mp4

# Create backup copy (identical for this test)
echo "Creating backup copy..."
cp "$SOURCE_VIDEO" /home/ga/Videos/backup/important_recording.mp4
chown ga:ga /home/ga/Videos/backup/important_recording.mp4

# Verify both files exist and are accessible
if [ ! -f /home/ga/Videos/original/important_recording.mp4 ]; then
    echo "ERROR: Original file not created"
    exit 1
fi

if [ ! -f /home/ga/Videos/backup/important_recording.mp4 ]; then
    echo "ERROR: Backup file not created"
    exit 1
fi

# Display file information for debugging
echo "Original file:"
ls -lh /home/ga/Videos/original/important_recording.mp4

echo "Backup file:"
ls -lh /home/ga/Videos/backup/important_recording.mp4

# Don't launch VLC yet - let the agent launch it as needed for verification
# The agent should be able to open files, check them, and create report

echo "=== Verify Backup Integrity Task Setup Complete ==="
echo "📝 Task Instructions:"
echo "  1. Compare original and backup files"
echo "  2. Original: /home/ga/Videos/original/important_recording.mp4"
echo "  3. Backup: /home/ga/Videos/backup/important_recording.mp4"
echo "  4. Verify using multiple methods:"
echo "     - File size comparison (ls -lh)"
echo "     - Metadata comparison (ffprobe)"
echo "     - Playback verification (open both in VLC)"
echo "  5. Create verification report:"
echo "     - Path: /home/ga/Documents/backup_verification_report.txt"
echo "     - Include: size comparison, metadata, playback status"
echo "     - Conclude with: SAFE TO DELETE ORIGINAL or NOT VERIFIED"
echo ""
echo "  Example ffprobe command:"
echo "  ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,width,height /home/ga/Videos/backup/important_recording.mp4"