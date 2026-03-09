#!/bin/bash
echo "=== Setting up change_widget_layout task ==="

source /workspace/utils/openbci_utils.sh || true

kill_openbci
launch_openbci_synthetic

echo "=== Task setup complete: GUI running in Synthetic mode with default layout ==="
echo "Agent should change the Layout to show 4 widget panels"
