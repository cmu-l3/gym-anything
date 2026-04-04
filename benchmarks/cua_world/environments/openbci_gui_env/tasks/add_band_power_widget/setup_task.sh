#!/bin/bash
echo "=== Setting up add_band_power_widget task ==="

source /workspace/utils/openbci_utils.sh || true

kill_openbci
launch_openbci_synthetic

echo "=== Task setup complete: GUI running in Synthetic mode with multi-panel layout ==="
echo "Agent should find a widget panel and switch it to Band Power"
