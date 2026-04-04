#!/bin/bash
echo "=== Exporting Z-Stack Projection results ==="

# Create results directory
mkdir -p /tmp/task_results

# Copy results if they exist
if [ -f /home/ga/Fiji_Data/results/max_projection.png ]; then
    cp /home/ga/Fiji_Data/results/max_projection.png /tmp/task_results/
    echo "Copied max_projection.png"
fi

if [ -f /home/ga/Fiji_Data/results/projection_stats.csv ]; then
    cp /home/ga/Fiji_Data/results/projection_stats.csv /tmp/task_results/
    echo "Copied projection_stats.csv"
fi

# List results
echo "Results in /tmp/task_results:"
ls -lh /tmp/task_results/ 2>/dev/null || echo "No results found"

echo "=== Export complete ==="
