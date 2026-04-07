#!/bin/bash
# Export results for multi_platform_distribution_transcode task
set -e

source /workspace/scripts/task_utils.sh

echo "Exporting results for multi_platform_distribution_transcode..."

# Copy deliverable files to /tmp/
mkdir -p /tmp/distribution_deliverables
for f in /home/ga/Videos/deliverables/*; do
    if [ -f "$f" ]; then
        cp -f "$f" "/tmp/distribution_deliverables/$(basename "$f")" 2>/dev/null || true
    fi
done

# Copy deliverables manifest
cp -f /home/ga/Documents/deliverables_manifest.json /tmp/distribution_manifest.json 2>/dev/null || true

# Copy ground truth
cp -f /tmp/.distribution_ground_truth.json /tmp/distribution_ground_truth.json 2>/dev/null || true

# List what was exported
echo "Exported files:"
ls -la /tmp/distribution_deliverables/ 2>/dev/null || echo "  No deliverable files found"
ls -la /tmp/distribution_manifest.json 2>/dev/null || echo "  No manifest found"

# Kill VLC
kill_vlc

echo "Export complete for multi_platform_distribution_transcode"
