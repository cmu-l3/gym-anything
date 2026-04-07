#!/bin/bash
echo "=== Setting up graphite_nagios_plugin task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready and populated with metrics
ensure_graphite_ready_for_task 120

# Remove any existing script or result files
rm -f /home/ga/check_graphite_metric.py
rm -f /tmp/graphite_nagios_plugin_result.json

# Record task start timestamp for anti-gaming (not strictly required for script tasks, but good practice)
date +%s > /tmp/graphite_nagios_plugin_start_ts

echo "=== graphite_nagios_plugin setup complete ==="