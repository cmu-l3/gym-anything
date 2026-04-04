#!/bin/bash
echo "=== Setting up VECM GDP Inflation Task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up previous artifacts
rm -f /home/ga/Documents/gretl_output/vecm_results.txt 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 2. Setup Gretl with usa.gdt
# This utility kills existing instances, restores the dataset, and launches Gretl
setup_gretl_task "usa.gdt" "vecm_task"

# 3. Verify dataset loaded correctly in background (for logging)
DATASET_CHECK=$(grep "usa.gdt" /home/ga/gretl_vecm_task.log 2>/dev/null || echo "not found")
echo "Dataset load check: $DATASET_CHECK"

echo "=== Task Setup Complete ==="
echo "Task: VECM Analysis of GDP and Inflation"
echo "Dataset: usa.gdt (loaded)"