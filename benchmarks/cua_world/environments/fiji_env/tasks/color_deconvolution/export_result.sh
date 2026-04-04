#!/bin/bash
echo "=== Exporting Color Deconvolution results ==="

# Create results directory
mkdir -p /tmp/task_results

# Copy results if they exist
for file in channel_1.png channel_2.png channel_1_stats.csv; do
    if [ -f "/home/ga/Fiji_Data/results/$file" ]; then
        cp "/home/ga/Fiji_Data/results/$file" /tmp/task_results/
        echo "Copied $file"
    fi
done

# List results
echo "Results in /tmp/task_results:"
ls -lh /tmp/task_results/ 2>/dev/null || echo "No results found"

echo "=== Export complete ==="
