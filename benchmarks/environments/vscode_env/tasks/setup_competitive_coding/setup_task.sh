#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Competitive Coding Task ==="

WORKSPACE_DIR="/home/ga/workspace/cp_contest"
TASK_ASSETS="/workspace/tasks/setup_competitive_coding/assets"

# Create workspace structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"
sudo -u ga mkdir -p "$WORKSPACE_DIR/test_cases"

# Create problem statement
cat > "$WORKSPACE_DIR/problem_statement.md" << 'EOF'
# Problem A: Sum of Two Numbers

Given two integers A and B, output their sum.

## Input
Two space-separated integers A and B (1 ≤ A, B ≤ 10^9)

## Output
Single integer: A + B

## Examples

### Example 1
**Input:**