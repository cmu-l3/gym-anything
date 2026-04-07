#!/bin/bash
# Setup script for openvsp_wing_error_fix task
# Injects three erroneous wing parameters into the Cessna-210 model

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_wing_error_fix ==="

# Ensure models directory exists
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy clean model to working location
cp /workspace/data/Cessna-210_metric.vsp3 "$MODELS_DIR/cessna210_corrupt.vsp3"
chmod 644 "$MODELS_DIR/cessna210_corrupt.vsp3"

# Kill any running OpenVSP instance
kill_openvsp

# Inject errors using Python XML manipulation
# NOTE: No ground truth is printed to stdout (Anti-Pattern 10 compliance)
python3 << 'PYEOF'
import sys

filepath = '/home/ga/Documents/OpenVSP/cessna210_corrupt.vsp3'

try:
    with open(filepath, 'r') as f:
        content = f.read()

    original_len = len(content)

    # Inject error 1: Root section Sweep (ID FRLKOYFIAPQ)
    content = content.replace(
        '<Sweep Value="0.000000000000000000e+00" ID="FRLKOYFIAPQ"/>',
        '<Sweep Value="4.200000000000000000e+01" ID="FRLKOYFIAPQ"/>'
    )
    # Inject error 2: Root section Twist (ID KCGUTVSHARU)
    content = content.replace(
        '<Twist Value="2.000000000000000000e+00" ID="KCGUTVSHARU"/>',
        '<Twist Value="2.200000000000000000e+01" ID="KCGUTVSHARU"/>'
    )
    # Inject error 3: Outboard section Dihedral (ID SURVMYSOGIV)
    content = content.replace(
        '<Dihedral Value="2.000000000000000000e+00" ID="SURVMYSOGIV"/>',
        '<Dihedral Value="-2.500000000000000000e+01" ID="SURVMYSOGIV"/>'
    )

    with open(filepath, 'w') as f:
        f.write(content)

    print("Setup complete.")
except Exception as e:
    print(f"Setup error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp recorded."

# Remove any stale result file
rm -f /tmp/openvsp_wing_error_fix_result.json

# Launch OpenVSP with the corrupted file so it's ready for the agent
launch_openvsp "$MODELS_DIR/cessna210_corrupt.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear in time — agent may need to launch it"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete: cessna210_corrupt.vsp3 ready ==="
