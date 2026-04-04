#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Play Video Result ==="

# Copy VLC log
if [ -f /tmp/vlc_play_task.log ]; then
    cp /tmp/vlc_play_task.log /tmp/vlc_play_result.log
    echo "✅ VLC log copied"
else
    echo "⚠️ VLC log not found"
fi

# Create completion marker file
echo "$(date)" > /tmp/vlc_play_completed.txt
echo "Video playback task completed" >> /tmp/vlc_play_completed.txt

# Check if VLC is still running
if is_vlc_running; then
    echo "VLC still running, closing..."
    kill_vlc ga
fi

echo "=== Export Complete ==="
