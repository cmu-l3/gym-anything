#!/bin/bash
echo "=== Setting up change_timeseries_scale task ==="

source /workspace/utils/openbci_utils.sh || true

kill_openbci
launch_openbci_synthetic

echo "=== Task setup complete: GUI running in Synthetic mode with Time Series widget ==="
echo "Agent should find the Vert Scale dropdown in the Time Series widget and set it to 1000 uV"
