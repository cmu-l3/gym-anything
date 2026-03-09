#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Delivery Specs Result ==="

# Check for verification report
REPORT_PATH="/home/ga/Documents/verification_report.txt"

if [ -f "$REPORT_PATH" ]; then
    echo "✅ Verification report found: $REPORT_PATH"
    cp "$REPORT_PATH" /tmp/vlc_verification_report.txt
    echo "Report contents:"
    cat "$REPORT_PATH"
else
    echo "⚠️ Verification report not found at expected location"
    
    # Look for any recently created text files in Documents
    RECENT_REPORT=$(find /home/ga/Documents -type f -name "*.txt" -mmin -5 2>/dev/null | grep -v "delivery_specs" | head -1)
    
    if [ -n "$RECENT_REPORT" ]; then
        echo "Found recent text file: $RECENT_REPORT"
        cp "$RECENT_REPORT" /tmp/vlc_verification_report.txt
    else
        # Create empty report so verifier can give feedback
        echo "No verification report created by agent" > /tmp/vlc_verification_report.txt
    fi
fi

# Copy ground truth and expected verdict for verifier
if [ -f /tmp/ground_truth.json ]; then
    cp /tmp/ground_truth.json /tmp/vlc_ground_truth.json
fi

if [ -f /tmp/expected_verdict.txt ]; then
    cp /tmp/expected_verdict.txt /tmp/vlc_expected_verdict.txt
fi

if [ -f /tmp/scenario_type.txt ]; then
    cp /tmp/scenario_type.txt /tmp/vlc_scenario_type.txt
fi

# Close VLC if running
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_verify_specs_completed.txt
echo "Verification specs task completed" >> /tmp/vlc_verify_specs_completed.txt

echo "=== Export Complete ==="