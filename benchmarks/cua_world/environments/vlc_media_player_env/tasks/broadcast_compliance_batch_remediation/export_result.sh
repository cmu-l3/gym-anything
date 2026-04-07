#!/bin/bash
# Export results for broadcast_compliance_batch_remediation task
set -e

source /workspace/scripts/task_utils.sh

echo "Exporting results for broadcast_compliance_batch_remediation..."

# Copy remediated files to /tmp/ for verification
for f in /home/ga/Videos/broadcast_ready/*.mp4; do
    if [ -f "$f" ]; then
        cp -f "$f" "/tmp/broadcast_ready_$(basename "$f")" 2>/dev/null || true
    fi
done

# Copy compliance report
cp -f /home/ga/Documents/compliance_report.json /tmp/broadcast_compliance_report.json 2>/dev/null || true

# Copy ground truth
cp -f /tmp/.broadcast_ground_truth.json /tmp/broadcast_ground_truth.json 2>/dev/null || true

# List what was exported
echo "Exported files:"
ls -la /tmp/broadcast_ready_*.mp4 2>/dev/null || echo "  No remediated video files found"
ls -la /tmp/broadcast_compliance_report.json 2>/dev/null || echo "  No compliance report found"

# Kill VLC
kill_vlc

echo "Export complete for broadcast_compliance_batch_remediation"
