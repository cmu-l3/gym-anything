#!/bin/bash
# Export result for vocal_stroop_acoustic_rt_analysis

set -e
echo "=== Exporting vocal_stroop_acoustic_rt_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

echo "=== vocal_stroop_acoustic_rt_analysis export complete ==="