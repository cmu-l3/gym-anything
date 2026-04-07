#!/bin/bash
# Export result for mfft_cognitive_style_analysis
# The verifier reads the JSON output directly via copy_from_env

set -e
echo "=== Exporting MFFT Cognitive Style Analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time for verification integrity
date +%s > /tmp/task_end_timestamp

# Take final screenshot for visual evidence logging
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/mfft_final_screenshot.png 2>/dev/null || true

echo "=== MFFT export complete ==="